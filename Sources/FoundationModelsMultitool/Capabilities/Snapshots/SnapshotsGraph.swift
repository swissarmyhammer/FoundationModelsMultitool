// `SnapshotsGraph` — the `snapshots` GraphQL endpoint (MT-13): the
// checkpoints of each session for the clients of the host, over the one
// `SnapshotStore` that the snapshots capability and `SnapshotHook` share.
//
// The schema is in `SnapshotsGraphSchema.swift`, and its change feed and
// `changes` subscription are in `SnapshotsGraphChanges.swift`. This file holds
// the endpoint and its coded errors.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import GraphQL

/// The `snapshots` GraphQL endpoint: the checkpoint queries and the
/// `rollbackTimeline` mutation of each session, over one ``SnapshotStore``.
///
/// The endpoint has the server scope: one endpoint serves each session, and a
/// call names its session with `sessionId`. The store takes a session key (the
/// key of the session lineage) and an owner (the session ID), so the host
/// gives a resolver that maps a session ID to its session key, and the session
/// ID is the owner.
///
/// - `Query.checkpoints(sessionId:)` gives the checkpoints of a session, oldest
///   first, and `Query.checkpoint(sessionId:index:)` gives one checkpoint, or
///   `null`. The `id` of a checkpoint is `<sessionId>:<index>`.
/// - `Mutation.rollbackTimeline(input:)` rolls the work tree of a session back
///   to a checkpoint, and gives the new rollback checkpoint (D95).
///
/// Its changes follow EXTRAS-9 rule 9: `Query.cursor` gives the cursor of the
/// newest change, and `Subscription.changes(after:sessionId:)` gives each
/// change after a cursor, one `SnapshotChange` for each new checkpoint of the
/// store: a take, a pending or rollback checkpoint of a rollback, or a change
/// made while the session key was closed. The new checkpoint is `added`, with
/// the id that `checkpoint(sessionId:index:)` gives. A subscription ends with
/// `RESYNC_REQUIRED` when a change after its cursor is lost. The endpoint
/// keeps the newest ``changeLogCapacity`` changes.
///
/// One store has one change log (EXTRAS-9 rule 1): each endpoint over the
/// same store, of each ``SnapshotsCapability`` value, gives the same cursor.
///
/// A session that the resolver does not know, or whose session key the store
/// has not open for it (for example a released session), gives no checkpoint,
/// and its rollback gives the `NOT_FOUND` of the toolkit. An external client
/// sees, rolls back and gets the changes of only the sessions that it owns;
/// the agent and a device of the user see each session.
///
/// The name rewrite takes `rollback` for `rollbackTimeline`, `snapshotChanges`
/// for `changes`, and the general query verbs, for example `listCheckpoints`
/// for `checkpoints`.
public struct SnapshotsGraph: GraphQLEndpoint {
    /// The name of the endpoint.
    public static let endpointName = "snapshots"

    /// The number of the newest changes that the change log of a store
    /// keeps: a subscription resumes after a cursor at most this many changes
    /// old, and a subscriber that falls this many changes behind gets
    /// `RESYNC_REQUIRED`.
    static let changeLogCapacity = 1024

    /// The other names that a call can write for the names of the schema:
    /// `rollback` for the `rollbackTimeline` mutation, and `snapshotChanges`
    /// for the `changes` subscription.
    static let rules = GraphQLNameRules(
        aliases: GraphQLAliasTable(
            byType: [
                "Mutation": ["rollbackTimeline": ["rollback"]],
                "Subscription": ["changes": ["snapshotChanges"]],
            ])
    )

    /// The name of the endpoint.
    public let name = endpointName

    /// The version of the schema.
    public let version = "1"

    /// The scope of the endpoint: the server.
    public let scope = GraphQLEndpointScope.server

    /// The root resolver over the store.
    private let resolver: SnapshotsGraphResolver

    /// The change log of the store, which the change stream of the store
    /// feeds; each endpoint over the store shares it.
    private let changes: SnapshotsGraphChangeFeed

    /// Makes the endpoint over a store.
    ///
    /// The change log of a store maps each session key of a change to its
    /// session ID with the `sessionId` resolver of the first endpoint over
    /// the store, so a host gives each endpoint over one store the same
    /// resolvers.
    ///
    /// - Parameters:
    ///   - store: The store that the host also gives to the snapshots
    ///     capability and to `SnapshotHook`.
    ///   - sessionKey: Gives the session key of a session ID, or `nil` for a
    ///     session that the host does not know.
    ///   - sessionId: The inverse of `sessionKey`: gives the session ID of a
    ///     session key, or `nil` for a key that the host does not know. A
    ///     checkpoint of an unknown key gives no change.
    public init(
        store: SnapshotStore, sessionKey: @escaping @Sendable (String) async -> String?,
        sessionId: @escaping @Sendable (String) async -> String?
    ) {
        self.init(
            store: store, sessionKey: sessionKey, sessionId: sessionId, changeLogCapacity: Self.changeLogCapacity)
    }

    /// Makes the endpoint over a store, with a change log of a given
    /// capacity when the store has no change log yet.
    ///
    /// - Parameters:
    ///   - store: The store.
    ///   - sessionKey: Gives the session key of a session ID, or `nil`.
    ///   - sessionId: Gives the session ID of a session key, or `nil`.
    ///   - changeLogCapacity: The number of the newest changes that a new
    ///     change log of the store keeps.
    init(
        store: SnapshotStore, sessionKey: @escaping @Sendable (String) async -> String?,
        sessionId: @escaping @Sendable (String) async -> String?, changeLogCapacity: Int
    ) {
        resolver = SnapshotsGraphResolver(store: store, sessionKey: sessionKey)
        changes = SnapshotsGraphChangeFeed.feed(of: store, sessionId: sessionId, capacity: changeLogCapacity)
    }

    /// The schema of the endpoint in SDL. The schema is built once for each
    /// process; when that build fails, the text is empty and each call throws
    /// the error of the build.
    public var schema: String {
        switch SnapshotsGraphAPI.builtSchema {
        case .success(let built):
            printSchema(schema: built.schema)
        case .failure:
            ""
        }
    }

    /// Runs one GraphQL document.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    /// - Returns: The GraphQL response as JSON text.
    /// - Throws: A fault that is not a GraphQL error, for example the error of
    ///   a schema build that failed.
    public func execute(
        query: String, variables: [String: Map], operationName: String?, viewer: GraphQLViewer?
    ) async throws -> String {
        try await api().respond(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: SnapshotsGraphContext(viewer: viewer, changes: changes))
    }

    /// Starts one GraphQL subscription: `changes(after:sessionId:)`, or its
    /// alias `snapshotChanges`. The stream gives one response for each new
    /// checkpoint that the viewer can see, and ends with one
    /// `RESYNC_REQUIRED` response when a change after the cursor is lost.
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - viewer: The client that makes the call, or `nil` for the agent.
    /// - Returns: The GraphQL response of each event as JSON text.
    /// - Throws: A fault that is not a GraphQL error, for example the error of
    ///   a schema build that failed.
    public func subscribe(
        query: String, variables: [String: Map], operationName: String?, viewer: GraphQLViewer?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await api().subscribe(
            to: query, variables: variables, operationName: operationName, rules: Self.rules,
            formattedWith: .sortedKeys, context: SnapshotsGraphContext(viewer: viewer, changes: changes))
    }

    /// The Graphiti engine of a call: the schema of the process and the
    /// resolver of this endpoint.
    ///
    /// - Returns: The engine.
    /// - Throws: The error of a schema build that failed.
    private func api() throws -> SnapshotsGraphAPI {
        SnapshotsGraphAPI(resolver: resolver, schema: try SnapshotsGraphAPI.builtSchema.get())
    }
}

/// The coded errors of the `snapshots` endpoint: one for each error of the
/// store, with an `UPPER_SNAKE` code in `extensions.code`.
///
/// ``SnapshotError/unavailable`` has no case here: for the endpoint it means
/// an unknown session, so ``coded(_:sessionId:)`` gives the `NOT_FOUND` of the
/// toolkit for it.
enum SnapshotsGraphError: CodedError, Equatable {
    /// `SNAPSHOTS_NOT_AVAILABLE`: an earlier open of the session or a timeline
    /// conflict of its key stopped the snapshots of the session.
    case notAvailable(cause: SnapshotUnavailableCause)

    /// `NO_TIMELINE`: the session key has no snapshot timeline.
    case noTimeline

    /// `INVALID_CHECKPOINT`: the timeline has no checkpoint with the index.
    case invalidCheckpoint(index: Int)

    /// `WORKING_DIRECTORY_MISMATCH`: the snapshots of the session key belong
    /// to a different working folder.
    case workingDirectoryMismatch

    /// `CONFLICTING_TIMELINE`: another writer changed the timeline after the
    /// session read it.
    case conflictingTimeline

    /// `UNREADABLE_TIMELINE`: the timeline holds a checkpoint that cannot be
    /// read.
    case unreadableTimeline

    /// `SESSION_KEY_OPEN`: the snapshots cannot be removed while a session has
    /// them open.
    case sessionKeyOpen

    /// `INVALID_SESSION_KEY`: the session key is not a valid name for its
    /// snapshots.
    case invalidSessionKey

    /// `FILE_NOT_IN_CHECKPOINT`: the path is not one of the files that the
    /// checkpoint changed.
    case fileNotInCheckpoint(path: String)

    /// The last sentence of each message after which the session gets no
    /// snapshot.
    private static let noMoreSnapshots = "The session gets no snapshot until it opens its session key again."

    /// Gives the coded error of an error of the store.
    ///
    /// - Parameters:
    ///   - error: The error of the store.
    ///   - sessionId: The session of the call.
    /// - Returns: The `NOT_FOUND` of the toolkit for
    ///   ``SnapshotError/unavailable``, else the case of this type.
    static func coded(_ error: SnapshotError, sessionId: String) -> any CodedError {
        switch error {
        case .unavailable:
            GraphQLToolkitError.notFound(kind: SnapshotsGraphResolver.sessionKind, id: sessionId)
        case .notAvailable(let cause):
            Self.notAvailable(cause: cause)
        case .noTimeline:
            Self.noTimeline
        case .invalidCheckpoint(let index):
            Self.invalidCheckpoint(index: index)
        case .workingDirectoryMismatch:
            Self.workingDirectoryMismatch
        case .timelineConflict:
            Self.conflictingTimeline
        case .unreadableTimeline:
            Self.unreadableTimeline
        case .sessionKeyOpen:
            Self.sessionKeyOpen
        case .invalidSessionKey:
            Self.invalidSessionKey
        case .fileNotInCheckpoint(let path):
            Self.fileNotInCheckpoint(path: path)
        }
    }

    /// The code of the error, for example `INVALID_CHECKPOINT`.
    var code: String {
        switch self {
        case .notAvailable: "SNAPSHOTS_NOT_AVAILABLE"
        case .noTimeline: "NO_TIMELINE"
        case .invalidCheckpoint: "INVALID_CHECKPOINT"
        case .workingDirectoryMismatch: "WORKING_DIRECTORY_MISMATCH"
        case .conflictingTimeline: "CONFLICTING_TIMELINE"
        case .unreadableTimeline: "UNREADABLE_TIMELINE"
        case .sessionKeyOpen: "SESSION_KEY_OPEN"
        case .invalidSessionKey: "INVALID_SESSION_KEY"
        case .fileNotInCheckpoint: "FILE_NOT_IN_CHECKPOINT"
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .notAvailable(let cause):
            "Snapshots are not available for this session: \(cause.rawValue). \(Self.noMoreSnapshots)"
        case .noTimeline:
            "The session key of this session has no snapshot timeline, thus the session has no checkpoint."
        case .invalidCheckpoint(let index):
            "There is no checkpoint \(index). A valid index is from 0 (the baseline, the state when the session "
                + "opened) to the count of checkpoints. Query checkpoints to see the indexes."
        case .workingDirectoryMismatch:
            "The snapshots of this session key belong to a different working folder, thus no snapshot is "
                + "available for this working folder."
        case .conflictingTimeline:
            "Another writer changed the snapshot timeline of this session after this session read it. The call "
                + "recorded no checkpoint. \(Self.noMoreSnapshots)"
        case .unreadableTimeline:
            "The snapshot timeline of this session holds a checkpoint that cannot be read. \(Self.noMoreSnapshots)"
        case .sessionKeyOpen:
            "The snapshots of this session cannot be removed while a session has them open. The checkpoints did "
                + "not change."
        case .invalidSessionKey:
            "The session key of this session is not a valid name for its snapshots, thus the session has no "
                + "snapshot."
        case .fileNotInCheckpoint(let path):
            "The file \(path) is not one of the files that this checkpoint changed. Query the files of the "
                + "checkpoint to see its paths."
        }
    }
}
