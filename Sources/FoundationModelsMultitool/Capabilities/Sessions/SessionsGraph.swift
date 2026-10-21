// `SessionsGraph` — the `sessions` GraphQL endpoint (MT-10): the sessions of
// the server and their messages for the clients of the host, over the same
// `SessionDirectory` that the `sessions` tool reads (session.md section 11).
//
// The schema is in `SessionsGraphSchema.swift`, its mutations are in
// `SessionsGraphMutations.swift`, its object types are in
// `SessionsGraphTypes.swift`, and its change feed and `changes` subscription
// are in `SessionsGraphChanges.swift`. This file holds the endpoint, its name
// rules, and the one endpoint of each directory.

import Foundation
import FoundationModelsExtras
import GraphQL
import Synchronization

/// The `sessions` GraphQL endpoint: the queries and the mutations of the
/// sessions of the server and of their messages, over one
/// ``SessionDirectory``.
///
/// The endpoint has the server scope. Its queries are flat root fields
/// (EXTRAS-9 rule 5):
///
/// - `Query.sessions(filter:)` gives the sessions that match a filter, the
///   newest first, at most 50 when the filter names no limit. The filter has
///   the rules of the `list sessions` op of the tool.
/// - `Query.session(id:)` gives one session, or `null`. A `Session` gives its
///   `parent`, its `startedBy`, its `children` (the subagent tree of a client)
///   and its `unreadCount`.
/// - `Query.inbox(sessionId:limit:)` gives the unread messages to a session,
///   the oldest first. It marks none read (D72): only the `read inbox` op of
///   the tool does.
///
/// Its mutations (EXTRAS-9 rule 7) have the names of the code-mode verbs of
/// the tool ops, and share their work and their correctives:
/// `startSession`, `tagSession`, `untagSession`, `renameSession`,
/// `archiveSession`, `sendMessage` and `replyMessage`, each with one `input`.
/// A client acts as its user, and a call with no viewer acts as the caller
/// session. A start from a client opens a tab only on that client (section
/// 11.5, D90).
///
/// Its changes follow EXTRAS-9 rule 9: `Query.cursor` gives the cursor of
/// the newest change, and `Subscription.changes(after:)` gives each change
/// after a cursor, one `SessionChange` for each event of the directory. A
/// started session, a new root session among them, is `added`; a change of
/// its facts, its state or its inbox, and its archive, is `changed`. A
/// subscription gives a viewer only the changes of the sessions that it can
/// see, and ends with `RESYNC_REQUIRED` when a change after its cursor is
/// lost. The endpoint keeps the newest ``changeLogCapacity`` changes.
///
/// An id argument reads a session id in any letter case, as the tool does,
/// and a text that is not a session id gives `INVALID_SESSION_ID` with the
/// corrective of the tool. Each refusal is a ``SessionsRefusal``.
///
/// The visibility rule of session.md section 11.3 (EXTRAS-9 rule 4) applies
/// to each result through ``SessionsVisibility``, the rule that the `sessions`
/// tool reads too: the agent and a device of the user see each session, and
/// an external client sees only the sessions that it owns, their subagents,
/// and the sessions that they started, to any depth. A mutation on a session
/// that the viewer cannot see gives the `NOT_FOUND` of the toolkit.
///
/// One directory has one endpoint (EXTRAS-9 rule 1): ``endpoint(of:)`` gives
/// the same instance for each call over the same directory, thus each copy of
/// ``SessionsTool``, of each session and each fork, gives the same endpoint,
/// with one change log and one cursor.
///
/// The name rewrite takes the general query verbs, for example `listSessions`
/// for `sessions`, and the aliases of ``rules``.
public final class SessionsGraph: GraphQLEndpoint {
    /// The name of the endpoint.
    public static let endpointName = "sessions"

    /// The number of the newest changes that the endpoint keeps: a
    /// subscription resumes after a cursor at most this many changes old,
    /// and a subscriber that falls this many changes behind gets
    /// `RESYNC_REQUIRED`.
    static let changeLogCapacity = 1024

    /// The other names that a call can write for the names of the schema
    /// (D86): `agent` and `folder` for the `agentId` and the `cwd` of a
    /// session, `sessionId` for the `id` of `session`, `id` for the
    /// `sessionId` of `inbox`, `sessionChanges` for the `changes`
    /// subscription, the bare verb of each mutation, and the names of the
    /// tool op of each mutation for the fields of its input.
    static let rules = GraphQLNameRules(
        aliases: GraphQLAliasTable(
            byType: SessionsGraphMutation.aliasTables.merging([
                "Session": ["agentId": ["agent"], "cwd": ["folder"]],
                "Subscription": ["changes": ["sessionChanges"]],
            ]) { mutation, _ in mutation },
            byField: ["Query.session": ["id": ["sessionId"]], "Query.inbox": ["sessionId": ["id"]]]))

    /// The name of the endpoint.
    public let name = endpointName

    /// The version of the schema.
    public let version = "1"

    /// The scope of the endpoint: the server.
    public let scope = GraphQLEndpointScope.server

    /// The directory that each call reads.
    private let directory: any SessionDirectory

    /// The change log of the endpoint, which the events of ``directory``
    /// feed from the moment the endpoint is made.
    private let changes: SessionsGraphChangeFeed

    /// Makes the endpoint over a directory, and starts its change feed. A
    /// caller outside this type gets the endpoint with ``endpoint(of:)``,
    /// which makes one for each directory.
    ///
    /// - Parameter directory: The directory that the `sessions` tool also
    ///   reads.
    private init(directory: any SessionDirectory) {
        self.directory = directory
        changes = SessionsGraphChangeFeed(directory: directory, capacity: Self.changeLogCapacity)
    }

    /// Gives the one endpoint of `directory` (EXTRAS-9 rule 1).
    ///
    /// The first call for a directory makes the endpoint, and each later call
    /// gives the same instance while a caller holds it. A directory with no
    /// identity, a value type, gets a new endpoint for each call. This call
    /// does no I/O.
    ///
    /// - Parameter directory: The session directory, for example the one of
    ///   the Router, or an `InMemorySessionDirectory` in a test.
    /// - Returns: The endpoint.
    public static func endpoint(of directory: any SessionDirectory) -> SessionsGraph {
        guard type(of: directory) is AnyObject.Type else {
            return SessionsGraph(directory: directory)
        }
        let key = ObjectIdentifier(directory as AnyObject)
        return endpoints.withLock { endpoints in
            endpoints = endpoints.filter { $0.value.endpoint != nil }
            if let endpoint = endpoints[key]?.endpoint {
                return endpoint
            }
            let endpoint = SessionsGraph(directory: directory)
            endpoints[key] = WeakEndpoint(endpoint: endpoint)
            return endpoint
        }
    }

    /// The schema of the endpoint in SDL. The schema is built once for each
    /// process; when that build fails, the text is empty and each call throws
    /// the error of the build.
    public var schema: String {
        switch SessionsGraphAPI.builtSchema {
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
            formattedWith: .sortedKeys, context: context(of: viewer))
    }

    /// Starts one GraphQL subscription: `changes(after:)`, or its alias
    /// `sessionChanges`. The stream gives one response for each change that
    /// the viewer can see, and ends with one `RESYNC_REQUIRED` response when
    /// a change after the cursor is lost.
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
            formattedWith: .sortedKeys, context: context(of: viewer))
    }

    /// The context of one call: the directory, read with the visibility of
    /// the viewer, and the change feed of the endpoint.
    ///
    /// - Parameter viewer: The client that makes the call, or `nil` for the
    ///   agent.
    /// - Returns: The context.
    private func context(of viewer: GraphQLViewer?) -> SessionsGraphContext {
        SessionsGraphContext(sessions: SessionsVisibility(directory: directory, viewer: viewer), changes: changes)
    }

    /// The Graphiti engine of a call: the schema of the process.
    ///
    /// - Returns: The engine.
    /// - Throws: The error of a schema build that failed.
    private func api() throws -> SessionsGraphAPI {
        SessionsGraphAPI(schema: try SessionsGraphAPI.builtSchema.get())
    }

    // MARK: - The one endpoint of each directory

    /// One endpoint that ``endpoints`` holds weakly: the table never keeps an
    /// endpoint, or its directory, alive. While a caller holds the endpoint,
    /// the endpoint holds its directory, thus no other directory can take the
    /// object identifier of the key.
    private struct WeakEndpoint {
        /// The endpoint, or `nil` after the last caller released it.
        weak var endpoint: SessionsGraph?
    }

    /// The endpoint of each directory that a caller holds now, by the object
    /// identifier of the directory.
    private static let endpoints = Mutex<[ObjectIdentifier: WeakEndpoint]>([:])
}
