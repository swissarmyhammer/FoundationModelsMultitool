// The GraphQL schema of the `snapshots` endpoint (MT-13): the object type,
// the arguments, the context, the resolver and the Graphiti API over one
// `SnapshotStore`.
//
// The resolver maps a session ID to its session key with the resolver that
// the host gives. The queries read the timeline of the key from disk with no
// owner, so they also read a closed key. The rollback passes the session ID as
// the owner, the same two values that `SnapshotsContext` reads from
// `HookSession.current` for the verbs.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import Graphiti
import GraphQL

// MARK: - Object type

/// The `Checkpoint` object: one checkpoint of the timeline of a session.
struct SnapshotsGraphCheckpoint: Codable, Sendable {
    /// The separator between the session ID and the index in ``id``.
    static let idSeparator = ":"

    /// The id of the checkpoint: `<sessionId>:<index>` (EXTRAS-9 rule 6).
    let id: ToolkitID

    /// The position of the checkpoint, from 1 for the oldest checkpoint.
    let index: Int

    /// The event that took the snapshot, as text.
    let trigger: String

    /// The tool call that took the snapshot, or `nil` for each trigger that
    /// is not a tool call.
    let toolCallId: String?

    /// The files that the checkpoint changed, relative to the work tree.
    let files: [String]

    /// The time of the snapshot.
    let at: DateTime

    /// The session that made the checkpoint: ``sessionId`` itself, or another
    /// session of the same working directory, whose sessions share one key.
    let owner: ToolkitID

    /// The session whose timeline holds the checkpoint. Not a field: the
    /// `changes` resolver codes its errors for this session.
    let sessionId: String

    /// The session key of ``sessionId``. Not a field: the `changes` resolver
    /// reads the diffs of this key.
    let sessionKey: String

    /// Makes the object of a checkpoint of the store.
    ///
    /// - Parameters:
    ///   - checkpoint: The checkpoint of the store.
    ///   - sessionId: The session whose timeline holds the checkpoint.
    ///   - sessionKey: The session key of `sessionId`.
    init(_ checkpoint: Checkpoint, sessionId: String, sessionKey: String) {
        self.sessionId = sessionId
        self.sessionKey = sessionKey
        id = Self.id(sessionId: sessionId, index: checkpoint.index)
        index = checkpoint.index
        trigger = SnapshotCheckpoint.text(of: checkpoint.trigger)
        toolCallId = Self.toolCallId(of: checkpoint.trigger)
        files = checkpoint.files
        at = DateTime(checkpoint.date)
        owner = ToolkitID(checkpoint.owner)
    }

    /// The id of a checkpoint: `<sessionId>:<index>`.
    ///
    /// - Parameters:
    ///   - sessionId: The session whose timeline holds the checkpoint.
    ///   - index: The index of the checkpoint.
    /// - Returns: The id.
    static func id(sessionId: String, index: Int) -> ToolkitID {
        ToolkitID([sessionId, String(index)].joined(separator: idSeparator))
    }

    /// The tool call of a trigger.
    ///
    /// - Parameter trigger: The event that took the snapshot.
    /// - Returns: The tool call ID of a tool trigger, or `nil`.
    private static func toolCallId(of trigger: SnapshotTrigger) -> String? {
        switch trigger {
        case .toolUse(let toolCallID, _):
            toolCallID
        case .manual, .pending, .rollback, .changedWhileClosed:
            nil
        }
    }
}

// MARK: - Arguments

/// The arguments of `Query.checkpoints`.
struct SnapshotsGraphCheckpointsArguments: Codable, Sendable {
    /// The session whose timeline the query reads.
    let sessionId: ToolkitID
}

/// The arguments of `Query.checkpoint`.
struct SnapshotsGraphCheckpointArguments: Codable, Sendable {
    /// The session whose timeline the query reads.
    let sessionId: ToolkitID

    /// The index of the checkpoint.
    let index: Int
}

/// The `RollbackTimelineInput` input object of `Mutation.rollbackTimeline`.
struct SnapshotsGraphRollbackInput: Codable, Sendable {
    /// The session whose work tree the mutation rolls back.
    let sessionId: ToolkitID

    /// The index of the checkpoint to restore. 0 is the baseline.
    let index: Int
}

/// The arguments of `Mutation.rollbackTimeline`.
struct SnapshotsGraphRollbackArguments: Codable, Sendable {
    /// The input object of the mutation.
    let input: SnapshotsGraphRollbackInput
}

// MARK: - Resolver and context

/// The context of one call of the `snapshots` endpoint.
struct SnapshotsGraphContext: GraphQLRunContext, GraphQLViewerScoping {
    /// The warnings of the call.
    let warnings = ResponseWarnings()

    /// The client of the call, or `nil` for the agent.
    let viewer: GraphQLViewer?

    /// The change feed of the store, for the `cursor` query and the
    /// `changes` subscription. A subscription holds it through its context.
    let changes: SnapshotsGraphChangeFeed

    /// Reads the diff of one file of one checkpoint, for `Checkpoint.changes`.
    let diff: SnapshotsGraphDiffProvider

    /// Tells if the client of the call can see a session (EXTRAS-9 rule 4):
    /// the agent and a device of the user see each session, and an external
    /// client sees only the sessions that it owns or that its connection
    /// started. The queries, `Checkpoint.changes` and the `changes`
    /// subscription read this rule.
    ///
    /// - Parameter sessionId: The session ID.
    /// - Returns: `true` when the client can see the session.
    func canSee(_ sessionId: String) -> Bool {
        admits { $0.isOwnerOrStarter(of: sessionId) }
    }

    /// Tells if the client of the call can roll a session back: the agent
    /// and a device of the user roll back each session, and an external
    /// client only the sessions that it owns now. A session that its
    /// connection started and another client took over stays visible, but
    /// the rollback is not its own to make.
    ///
    /// - Parameter sessionId: The session ID.
    /// - Returns: `true` when the client can roll the session back.
    func canRollBack(_ sessionId: String) -> Bool {
        admits { $0.owns(sessionId) }
    }
}

/// The root resolver of the `snapshots` endpoint over the store.
struct SnapshotsGraphResolver: Sendable {
    /// The kind of the id of a `NOT_FOUND` error: the session ID.
    static let sessionKind = "session"

    /// The store that the capability and `SnapshotHook` share.
    let store: SnapshotStore

    /// Gives the session key of a session ID, or `nil` for a session that the
    /// host does not know.
    let sessionKey: @Sendable (String) async -> String?

    /// Resolves `Query.checkpoints`.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the viewer.
    ///   - arguments: The session ID.
    /// - Returns: The checkpoints, oldest first, of an open or a closed
    ///   session key. No checkpoint for a session that the viewer cannot see,
    ///   that the host does not know, or whose session key has no timeline.
    /// - Throws: A ``SnapshotsGraphError`` for each other store error.
    func checkpoints(
        context: SnapshotsGraphContext, arguments: SnapshotsGraphCheckpointsArguments
    ) async throws -> [SnapshotsGraphCheckpoint] {
        try await timeline(of: arguments.sessionId.text, context: context) ?? []
    }

    /// Resolves `Query.checkpoint`.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the viewer.
    ///   - arguments: The session ID and the index.
    /// - Returns: The checkpoint, or `nil` when the timeline has no checkpoint
    ///   with the index, or when ``checkpoints(context:arguments:)`` gives no
    ///   checkpoint.
    /// - Throws: A ``SnapshotsGraphError`` for each other store error.
    func checkpoint(
        context: SnapshotsGraphContext, arguments: SnapshotsGraphCheckpointArguments
    ) async throws -> SnapshotsGraphCheckpoint? {
        try await timeline(of: arguments.sessionId.text, context: context)?.first { $0.index == arguments.index }
    }

    /// Resolves `Mutation.rollbackTimeline` (D95): the work tree becomes the
    /// tree after the checkpoint, and the rollback is a new checkpoint at the
    /// end of the timeline.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the viewer.
    ///   - arguments: The session ID and the index of the checkpoint.
    /// - Returns: The new rollback checkpoint, or `nil` when the work tree
    ///   already equals the checkpoint: then the store adds no checkpoint.
    /// - Throws: `NOT_FOUND` of the toolkit for a session that the viewer
    ///   cannot roll back, that the host does not know, or that has its
    ///   session key not open; a ``SnapshotsGraphError`` for each other store
    ///   error.
    func rollbackTimeline(
        context: SnapshotsGraphContext, arguments: SnapshotsGraphRollbackArguments
    ) async throws -> SnapshotsGraphCheckpoint? {
        let sessionId = arguments.input.sessionId.text
        guard context.canRollBack(sessionId), let key = await sessionKey(sessionId) else {
            throw GraphQLToolkitError.notFound(kind: Self.sessionKind, id: sessionId)
        }
        do {
            let checkpoint = try await store.rollback(sessionKey: key, owner: sessionId, to: arguments.input.index)
            return checkpoint.map { SnapshotsGraphCheckpoint($0, sessionId: sessionId, sessionKey: key) }
        } catch let error as SnapshotError {
            throw SnapshotsGraphError.coded(error, sessionId: sessionId)
        }
    }

    /// Reads the timeline of a session from disk. The read needs no owner, so
    /// it reads the timeline of an open key and of a closed key (for example
    /// the key of a released session) alike.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID.
    ///   - context: The context of the call, which gives the viewer.
    /// - Returns: The checkpoints, oldest first, or `nil` for a session that
    ///   the viewer cannot see, that the host does not know, or whose session
    ///   key has no timeline.
    /// - Throws: A ``SnapshotsGraphError`` for each other store error.
    private func timeline(of sessionId: String, context: SnapshotsGraphContext) async throws
        -> [SnapshotsGraphCheckpoint]?
    {
        guard context.canSee(sessionId), let key = await sessionKey(sessionId) else {
            return nil
        }
        do {
            return try await store.timelineCheckpoints(sessionKey: key).map { checkpoint in
                SnapshotsGraphCheckpoint(checkpoint, sessionId: sessionId, sessionKey: key)
            }
        } catch SnapshotError.noTimeline {
            return nil
        } catch let error as SnapshotError {
            throw SnapshotsGraphError.coded(error, sessionId: sessionId)
        }
    }
}

// MARK: - The API

/// The Graphiti engine of the `snapshots` endpoint.
struct SnapshotsGraphAPI: API {
    /// The schema of the endpoint, built once. It does not depend on a store:
    /// the resolver that a call gives holds the store.
    static let builtSchema = Result { try makeSchema() }

    /// The text of the description of the `sessionId` argument of a query.
    private static let sessionIdDescription =
        "The id of the session. An external client names only a session that it owns or that its connection "
        + "started."

    /// The text of the description of the `sessionId` of a rollback.
    private static let rollbackSessionIdDescription =
        "The id of the session. An external client rolls back only a session that it owns."

    /// The root resolver.
    let resolver: SnapshotsGraphResolver

    /// The schema.
    let schema: Schema<SnapshotsGraphResolver, SnapshotsGraphContext>

    /// Builds the schema of the endpoint. The `cursor` query, the `changes`
    /// subscription and its type are in `SnapshotsGraphChanges.swift`, and
    /// the `FileChange` type of `Checkpoint.changes` is in
    /// `SnapshotsGraphFileChanges.swift`.
    ///
    /// - Returns: The schema.
    /// - Throws: An error of the schema builder.
    private static func makeSchema() throws -> Schema<SnapshotsGraphResolver, SnapshotsGraphContext> {
        try SchemaBuilder(SnapshotsGraphResolver.self, SnapshotsGraphContext.self)
            .addToolkitScalars()
            .addToolkitIDScalar()
            .add {
                Type(SnapshotsGraphCheckpoint.self, as: "Checkpoint") {
                    Field("id", at: \.id).description("The id of the checkpoint: <sessionId>:<index>.")
                    Field("index", at: \.index)
                        .description("The position of the checkpoint, from 1 for the oldest checkpoint.")
                    Field("trigger", at: \.trigger)
                        .description(
                            "What took the snapshot: 'tool <name> (call <id>)', 'label <text>', 'manual', "
                                + "'rollback to <index>', 'pending', or 'changed while closed'.")
                    Field("toolCallId", at: \.toolCallId)
                        .description("The tool call that took the snapshot, or null when no tool call took it.")
                    Field("files", at: \.files).description("The files that the checkpoint changed.")
                    Field("at", at: \.at).description("The time of the snapshot.")
                    Field("owner", at: \.owner)
                        .description(
                            "The session that made the checkpoint: this session, or another session of the same "
                                + "working directory, which shares its checkpoints.")
                    Field("changes", at: SnapshotsGraphCheckpoint.changes)
                        .description(
                            "Each file that the checkpoint changed, with its unified diff. Select it only when you "
                                + "need the diffs: each one is read from disk.")
                }
                .description("One checkpoint: a recorded change of the work tree of a session.")
                fileChangeType()
                Input(SnapshotsGraphRollbackInput.self, as: "RollbackTimelineInput") {
                    InputField("sessionId", at: \.sessionId).description(Self.rollbackSessionIdDescription)
                    InputField("index", at: \.index)
                        .description("The index of the checkpoint to restore. 0 is the baseline.")
                }
                .description("The checkpoint to roll the work tree of a session back to.")
                changeType()
            }
            .addQuery {
                Field("checkpoints", at: SnapshotsGraphResolver.checkpoints) {
                    Argument("sessionId", at: \.sessionId).description(Self.sessionIdDescription)
                }
                .description("The checkpoints of a session, oldest first. An unknown session gives none.")
                Field("checkpoint", at: SnapshotsGraphResolver.checkpoint) {
                    Argument("sessionId", at: \.sessionId).description(Self.sessionIdDescription)
                    Argument("index", at: \.index).description("The index of the checkpoint, from 1.")
                }
                .description("One checkpoint of a session, or null when the session has no such checkpoint.")
                cursorField()
            }
            .addMutation {
                Field("rollbackTimeline", at: SnapshotsGraphResolver.rollbackTimeline) {
                    Argument("input", at: \.input).description("The session and the checkpoint to restore.")
                }
                .description(
                    "Makes the work tree of a session equal to the tree after a checkpoint. The rollback is a new "
                        + "checkpoint at the end of the timeline, which this gives, and the later checkpoints stay. "
                        + "Null when the work tree already equals that checkpoint. An unknown session gives "
                        + "NOT_FOUND.")
            }
            .addSubscription {
                changesField()
            }
            .build()
    }
}
