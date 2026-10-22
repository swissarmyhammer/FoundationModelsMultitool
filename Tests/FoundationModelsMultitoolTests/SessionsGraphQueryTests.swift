// `SessionsGraphQueryTests` — the behavioral suite of the queries of the
// `sessions` GraphQL endpoint (MT-10, task `^9c0fp9m`).
//
// Each case registers its sessions in its own `InMemorySessionDirectory`, and
// reads them through `SessionsGraph` with one viewer: the agent (no viewer), a
// device of the user, or an external client. No case reads a clock or waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the queries of the `sessions` GraphQL endpoint: the
/// endpoint contract, the `sessions`, `session` and `inbox` queries, and the
/// visibility of each viewer kind.
@Suite("SessionsGraphQueryTests", .ownsTemporaryDirectories)
struct SessionsGraphQueryTests {

    // MARK: - Constants

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// The title of the owned session of the tree.
    private static let ownedTitle = "Review the parser"

    /// The tags of the owned session of the tree, not sorted.
    private static let ownedTags: Set<String> = ["review", "api", "parser"]

    /// The last summary of the owned session of the tree.
    private static let lastSummary = "The parser handles empty input now."

    /// The most sessions that `sessions` gives with no limit.
    private static let defaultListLimit = 50

    /// A limit that the `sessions` cases name.
    private static let smallLimit = 2

    /// More sessions than ``defaultListLimit``, newer than the owned session
    /// of a case.
    private static let crowdSize = 60

    /// The selection of each session that a case reads.
    private static let sessionSelection =
        "{ id agentId agentName cwd title tags kind state origin createdAt updatedAt lastSummary isLive }"

    /// The `sessions` query with a filter.
    private static let sessionsQuery = "query($filter: SessionFilter) { sessions(filter: $filter) { id } }"

    /// The `session` query of one id.
    private static let sessionQuery = "query($id: ID!) { session(id: $id) \(sessionSelection) }"

    /// The `session` query of one id, with the parent, the starter and the
    /// children.
    private static let relativesQuery =
        "query($id: ID!) { session(id: $id) { id parent { id } startedBy { id } children { id } } }"

    /// The `session` query of one id, with the count of its unread messages.
    private static let unreadQuery = "query($id: ID!) { session(id: $id) { unreadCount } }"

    /// The `inbox` query of one session.
    private static let inboxQuery =
        "query($id: ID!) { inbox(sessionId: $id) { id from { session { id } clientId } to { id } text inReplyTo "
        + "sentAt chainDepth isRead } }"

    /// The `inbox` query of one session, with a limit.
    private static let limitedInboxQuery =
        "query($id: ID!, $limit: Int) { inbox(sessionId: $id, limit: $limit) { text } }"

    /// The text of the first message of the inbox cases.
    private static let firstText = "Please look at the failing test."

    /// The text of the second message of the inbox cases.
    private static let secondText = "The build is green again."

    /// The op string of the `read inbox` operation of the tool.
    private static let readInboxOp = "read inbox"

    /// The name of the golden file of the schema, under
    /// `Tests/FoundationModelsMultitoolTests/Goldens`.
    private static let goldenFileName = "sessions.graphql"

    /// The root query of the newest cursor.
    private static let cursorQuery = "{ cursor }"

    /// The subscription of the `sessionChanges` alias probe, with every field
    /// of a change.
    private static let sessionChangesSubscription =
        "subscription($after: String) { sessionChanges(after: $after) { cursor added changed removed } }"

    // MARK: - Helpers

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The sessions of the visibility cases, registered in this order in one
    /// directory. An external client that owns ``owned`` sees ``owned``,
    /// ``subagent``, ``started``, ``startedByStarted`` and
    /// ``deepSubagent``, and none of the others.
    private struct Tree {
        /// The directory that holds each session.
        let directory = InMemorySessionDirectory()

        /// A root session that the external client owns.
        let owned = Fixtures.summary(tags: ownedTags, title: ownedTitle)

        /// A subagent of ``owned``.
        let subagent: SessionSummary

        /// A fork of ``owned``: a fork is not a subagent.
        let fork: SessionSummary

        /// A root session that ``owned`` started.
        let started: SessionSummary

        /// A root session that ``started`` started.
        let startedByStarted: SessionSummary

        /// A subagent of ``startedByStarted``.
        let deepSubagent: SessionSummary

        /// A root session with no link to ``owned``.
        let stranger = Fixtures.summary()

        /// A subagent of ``stranger``.
        let strangerSubagent: SessionSummary

        /// Makes the sessions and registers them.
        init() {
            subagent = Fixtures.summary(kind: .subagent, parentID: owned.id)
            fork = Fixtures.summary(kind: .fork, parentID: owned.id)
            started = Fixtures.summary(startedBy: owned.id)
            startedByStarted = Fixtures.summary(startedBy: started.id)
            deepSubagent = Fixtures.summary(kind: .subagent, parentID: startedByStarted.id)
            strangerSubagent = Fixtures.summary(kind: .subagent, parentID: stranger.id)
            for session in all {
                directory.register(session)
            }
        }

        /// Each session, in the order of registration.
        var all: [SessionSummary] {
            [owned, subagent, fork, started, startedByStarted, deepSubagent, stranger, strangerSubagent]
        }

        /// The id of each session that the owner of ``owned`` sees.
        var visibleToOwner: Set<String> {
            Set([owned, subagent, started, startedByStarted, deepSubagent].map(\.id.ulidString))
        }

        /// The endpoint over ``directory``.
        var graph: SessionsGraph {
            SessionsGraph.endpoint(of: directory)
        }
    }

    /// The setup of the `sessionChanges` alias probe: an endpoint, the cursor
    /// that it gave, and one live root session registered after that cursor,
    /// so the first change after the cursor adds that session.
    private struct RegisteredAfterCursor {
        /// The directory that holds ``session``.
        let directory = InMemorySessionDirectory()

        /// The live root session registered after ``cursor``.
        let session = Fixtures.summary()

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly, and a new endpoint has a
        /// new change log that cannot resume after ``cursor``.
        let graph: SessionsGraph

        /// The cursor that ``graph`` gave before ``session`` was registered.
        let cursor: String

        /// Reads the cursor of the endpoint, then registers ``session``.
        ///
        /// - Throws: What the endpoint throws, or an error when the response
        ///   has no cursor.
        init() async throws {
            graph = SessionsGraph.endpoint(of: directory)
            cursor = try #require(try await run(cursorQuery, on: graph).data?["cursor"] as? String)
            directory.register(session)
        }

        /// The variables of ``sessionChangesSubscription``: resume after
        /// ``cursor``.
        var variables: [String: Map] {
            ["after": .string(cursor)]
        }
    }

    /// Runs one document on `graph`.
    ///
    /// - Parameters:
    ///   - query: The document.
    ///   - variables: The values of the variables.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    private static func run(
        _ query: String, variables: [String: Map] = [:], viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await graph.execute(query: query, variables: variables, operationName: nil, viewer: viewer))
    }

    /// Runs the `sessions` query with `filter`.
    ///
    /// - Parameters:
    ///   - filter: The filter, or no filter.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws.
    private static func sessions(
        filter: Map = .null, viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> GraphQLReply {
        try await run(sessionsQuery, variables: ["filter": filter], viewer: viewer, on: graph)
    }

    /// The id of each session of a `sessions` response.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The ids, in order.
    /// - Throws: An error when the response has no `sessions` list.
    private static func ids(of reply: GraphQLReply) throws -> [String] {
        try reply.list("sessions").compactMap { $0["id"] as? String }
    }

    /// Runs `query` with the variable `id`.
    ///
    /// - Parameters:
    ///   - query: The document, with the variable `$id`.
    ///   - id: The value of `$id`.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws.
    private static func run(
        _ query: String, id: String, viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> GraphQLReply {
        try await run(query, variables: ["id": .string(id)], viewer: viewer, on: graph)
    }

    /// The `ownedByViewer` and `hasOwner` fields of one session.
    private struct Ownership: Equatable {
        /// A session that the viewer owns.
        static let ownedByViewer = Ownership(ownedByViewer: true, hasOwner: true)

        /// A session that another client owns.
        static let ownedByOtherClient = Ownership(ownedByViewer: false, hasOwner: true)

        /// A session that no client owns, or a read with no viewer.
        static let noOwner = Ownership(ownedByViewer: false, hasOwner: false)

        /// The `ownedByViewer` field.
        let ownedByViewer: Bool?

        /// The `hasOwner` field.
        let hasOwner: Bool?
    }

    /// The `session` query of one id, with its two ownership fields.
    private static let ownershipQuery = "query($id: ID!) { session(id: $id) { ownedByViewer hasOwner } }"

    /// Reads the ownership fields of each session, one `session` query each.
    ///
    /// - Parameters:
    ///   - sessions: The sessions, which the viewer must see.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - tree: The tree that holds the sessions.
    /// - Returns: The fields of each session, in order.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws, or an error when
    ///   a response has no `session` object.
    private static func ownership(
        of sessions: [SessionSummary], viewer: GraphQLViewer?, on tree: Tree
    ) async throws -> [Ownership] {
        var fields: [Ownership] = []
        // A loop and not a `map`: each read awaits the endpoint.
        for session in sessions {
            let object = try await run(ownershipQuery, id: session.id.ulidString, viewer: viewer, on: tree.graph)
                .object("session")
            fields.append(
                Ownership(ownedByViewer: object["ownedByViewer"] as? Bool, hasOwner: object["hasOwner"] as? Bool))
        }
        return fields
    }

    /// A device of the user, which owns no session.
    private static let deviceViewer = GraphQLViewer(clientId: deviceClientId, trust: .userDevice)

    /// Sends `text` from the session `sender` to the session `target`, in a
    /// turn of the sender.
    ///
    /// - Parameters:
    ///   - text: The text of the message.
    ///   - sender: The sending session.
    ///   - target: The target session.
    ///   - directory: The directory.
    /// - Throws: What the directory throws.
    private static func send(
        _ text: String, from sender: ULID, to target: ULID, in directory: InMemorySessionDirectory
    ) async throws {
        try directory.startUserTurn(of: sender)
        _ = try await directory.send(OutgoingSessionMessage(from: .session(sender), to: .session(target), text: text))
    }

    /// Sends `text` from the device of the user to the session `target`.
    ///
    /// - Parameters:
    ///   - text: The text of the message.
    ///   - target: The target session.
    ///   - directory: The directory.
    /// - Throws: What the directory throws.
    private static func sendFromTheUser(
        _ text: String, to target: ULID, in directory: InMemorySessionDirectory
    ) async throws {
        _ = try await directory.send(
            OutgoingSessionMessage(from: .user(clientID: deviceClientId), to: .session(target), text: text))
    }

    /// Runs the `inbox` query of `id`.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The messages of the response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws, or an error when
    ///   the response has no `inbox` list.
    private static func inbox(
        of id: ULID, viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> [[String: Any]] {
        try await run(inboxQuery, id: id.ulidString, viewer: viewer, on: graph).list("inbox")
    }

    /// Registers `count` live root sessions in `directory`.
    ///
    /// - Parameters:
    ///   - count: The number of sessions.
    ///   - directory: The directory.
    private static func registerSessions(_ count: Int, in directory: InMemorySessionDirectory) {
        for _ in 0..<count {
            directory.register(Fixtures.summary())
        }
    }

    // MARK: - The endpoint contract

    /// The endpoint has the name `sessions`, the version `1` and the server
    /// scope.
    @Test("the endpoint is sessions, version 1, with the server scope")
    func theEndpointFacts() {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        #expect(graph.name == "sessions")
        #expect(graph.version == "1")
        #expect(graph.scope == .server)
    }

    /// The `sessions` tool is a `GraphQLEndpointTool`, and gives one
    /// endpoint: the `sessions` endpoint over its directory.
    @Test("the sessions tool gives the sessions endpoint")
    func theToolGivesTheEndpoint() throws {
        let directory = InMemorySessionDirectory()
        let tool: any Tool = try SessionsTool(directory: directory)

        let endpoints = try #require((tool as? any GraphQLEndpointTool)?.graphQLEndpoints)

        #expect(endpoints.count == 1)
        let graph = try #require(endpoints.first as? SessionsGraph)
        #expect(graph === SessionsGraph.endpoint(of: directory))
    }

    /// Each copy of the tool, and each tool over the same directory, gives
    /// the same endpoint instance (EXTRAS-9 rule 1).
    @Test("two copies of the tool, and two tools over one directory, give the same endpoint")
    func copiesGiveTheSameEndpoint() throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)
        let copy = tool
        let other = try SessionsTool(directory: directory)

        let endpoint = try #require(tool.graphQLEndpoints.first as? SessionsGraph)
        let copiedEndpoint = try #require(copy.graphQLEndpoints.first as? SessionsGraph)
        let otherEndpoint = try #require(other.graphQLEndpoints.first as? SessionsGraph)

        #expect(endpoint === copiedEndpoint)
        #expect(endpoint === otherEndpoint)
    }

    /// Two directories have two endpoints: an endpoint reads one directory.
    @Test("two directories give two endpoints")
    func twoDirectoriesGiveTwoEndpoints() {
        let first = SessionsGraph.endpoint(of: InMemorySessionDirectory())
        let second = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        #expect(first !== second)
    }

    /// The endpoint conforms to the toolkit conventions, rule 9 among them.
    /// The `listSessions` probe checks that its response reports the rewrite
    /// to `sessions` and has no error. The `sessionChanges` probe resumes
    /// after the cursor that the endpoint gave before one session was
    /// registered, and checks that its first response reports the rewrite to
    /// `changes` and has no error. The probe does not read the data of that
    /// response; ``theFirstSessionChangesResponseAddsTheRegisteredSession()``
    /// checks that the data is the change of the registered session.
    @Test("the endpoint conforms, with the listSessions and sessionChanges alias probes")
    func theEndpointConforms() async throws {
        let setup = try await RegisteredAfterCursor()
        let probes = [
            GraphQLAliasProbe(query: "{ listSessions { id } }", from: "listSessions", to: "sessions"),
            GraphQLAliasProbe(
                query: Self.sessionChangesSubscription, variables: setup.variables, from: "sessionChanges",
                to: "changes", kind: .subscription),
        ]

        let problems = await GraphQLEndpointConformance.problems(
            of: setup.graph, scope: .server, probes: probes, codes: SessionsRefusal.codes, clock: ManualRunClock())

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    /// The first response of the subscription of the `sessionChanges` probe,
    /// after the same cursor, is the change of the session registered after
    /// that cursor: `added` holds the id of that session, and `changed` and
    /// `removed` are empty.
    @Test("the first response of the sessionChanges probe subscription adds the registered session")
    func theFirstSessionChangesResponseAddsTheRegisteredSession() async throws {
        let setup = try await RegisteredAfterCursor()
        var responses = try await setup.graph.subscribe(
            query: Self.sessionChangesSubscription, variables: setup.variables, operationName: nil, viewer: nil
        ).makeAsyncIterator()

        let reply = try GraphQLReply(json: try #require(try await responses.next()))

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let change = try reply.object("sessionChanges")
        #expect(change["added"] as? [String] == [setup.session.id.ulidString])
        #expect(change["changed"] as? [String] == [])
        #expect(change["removed"] as? [String] == [])
    }

    /// Each type, field, argument, enum value and input field of the schema
    /// has a description, because a client learns the schema with
    /// introspection.
    @Test("each part of the schema has a description")
    func eachPartOfTheSchemaHasADescription() throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let undescribed = try GraphQLSchemaDescriptions.undescribed(in: buildSchema(source: graph.schema))

        #expect(undescribed.isEmpty, "undescribed: \(undescribed)")
    }

    /// The SDL schema is the schema in the golden file.
    @Test("the schema matches the golden file")
    func theSchemaMatchesTheGoldenFile() {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())
        let goldenFile = RepositoryFile.root
            .appendingPathComponent("Tests/FoundationModelsMultitoolTests/Goldens")
            .appendingPathComponent(Self.goldenFileName)

        let problems = GraphQLSchemaGolden.problems(of: graph.schema, against: goldenFile)

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    /// A directory that is a value type has no identity, thus each call
    /// makes a new endpoint, and each endpoint reads that directory.
    @Test("a value-type directory gets a new endpoint for each call, over that directory")
    func aValueTypeDirectoryGetsANewEndpoint() async throws {
        let backing = InMemorySessionDirectory()
        let session = Fixtures.summary()
        backing.register(session)
        let directory = ForwardingSessionDirectory(backing: backing)

        let first = SessionsGraph.endpoint(of: directory)
        let second = SessionsGraph.endpoint(of: directory)
        let ids = try Self.ids(of: await Self.sessions(on: first))

        #expect(first !== second)
        #expect(ids == [session.id.ulidString])
    }

    /// A `MultiTool` with the `sessions` tool gives its endpoint through
    /// `graphQLEndpoints`.
    @Test("MultiTool gives the sessions endpoint of withSessions")
    func multiToolGivesTheSessionsEndpoint() throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())
        let registry = try MultiTool.Builder().withSessions(tool).buildRegistry()

        let names = MultiTool(registry: registry).graphQLEndpoints.map(\.name)

        #expect(names == [SessionsGraph.endpointName])
    }

    // MARK: - Visibility of each viewer kind

    /// The agent of the session, a call with no viewer, sees each session.
    @Test("the agent sees each session")
    func theAgentSeesEachSession() async throws {
        let tree = Tree()

        let ids = try Self.ids(of: await Self.sessions(on: tree.graph))

        #expect(Set(ids) == Set(tree.all.map(\.id.ulidString)))
    }

    /// A device of the user sees each session, also the sessions that it
    /// does not own.
    @Test("a device of the user sees each session")
    func aUserDeviceSeesEachSession() async throws {
        let tree = Tree()

        let ids = try Self.ids(of: await Self.sessions(viewer: Self.deviceViewer, on: tree.graph))

        #expect(Set(ids) == Set(tree.all.map(\.id.ulidString)))
    }

    /// An external client sees the sessions that it owns, their subagents,
    /// and the sessions that they started, to any depth; not a fork, and no
    /// other session.
    @Test("an external viewer sees only its sessions, their subagents and the sessions they started")
    func anExternalViewerSeesOnlyItsTree() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer.external(owning: [tree.owned.id.ulidString])

        let ids = try Self.ids(of: await Self.sessions(viewer: viewer, on: tree.graph))

        #expect(Set(ids) == tree.visibleToOwner)
        #expect(ids.count == tree.visibleToOwner.count)
    }

    /// An external client that owns no session sees none.
    @Test("an external viewer that owns no session sees none")
    func anExternalViewerWithNoSessionSeesNone() async throws {
        let tree = Tree()

        let ids = try Self.ids(of: await Self.sessions(viewer: GraphQLViewer.external(), on: tree.graph))

        #expect(ids.isEmpty)
    }

    /// The limit of an external viewer counts only the sessions that it can
    /// see: its session is in the list after more newer sessions than the
    /// limit that it cannot see.
    @Test("the limit of an external viewer counts only the sessions it sees")
    func theLimitCountsOnlyVisibleSessions() async throws {
        let tree = Tree()
        Self.registerSessions(Self.crowdSize, in: tree.directory)
        let viewer = GraphQLViewer.external(owning: [tree.owned.id.ulidString])

        let ids = try Self.ids(of: await Self.sessions(viewer: viewer, on: tree.graph))

        #expect(Set(ids) == tree.visibleToOwner)
    }

    /// `session(id:)` gives a session that the external viewer can see, and
    /// `null` with no error for one that it cannot see, so the response does
    /// not tell that the session exists.
    @Test("session(id:) gives a visible session, and null for a hidden one")
    func sessionIsNullWhenHidden() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer.external(owning: [tree.owned.id.ulidString])

        let visible = try await Self.run(
            Self.sessionQuery, id: tree.deepSubagent.id.ulidString, viewer: viewer, on: tree.graph)
        let hidden = try await Self.run(Self.sessionQuery, id: tree.fork.id.ulidString, viewer: viewer, on: tree.graph)

        #expect(try visible.object("session")["id"] as? String == tree.deepSubagent.id.ulidString)
        #expect(hidden.codes.isEmpty)
        #expect(hidden.isNull("session"))
    }

    /// An external client also sees the sessions that its connection
    /// started and no longer owns, their subagents, and the sessions that
    /// they started; no other session.
    @Test("an external viewer sees the sessions that its connection started, and their tree")
    func anExternalViewerSeesTheSessionsItStarted() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer.external(started: [tree.started.id.ulidString])
        let visibleToStarter = Set([tree.started, tree.startedByStarted, tree.deepSubagent].map(\.id.ulidString))

        let ids = try Self.ids(of: await Self.sessions(viewer: viewer, on: tree.graph))

        #expect(Set(ids) == visibleToStarter)
        #expect(ids.count == visibleToStarter.count)
    }

    // MARK: - Ownership of each viewer kind

    /// An external client reads `ownedByViewer` from the sessions that it
    /// owns, and `hasOwner` from the sessions that any client owns: its own
    /// session, a subagent that another client owns, and a session that no
    /// client owns.
    @Test("an external viewer reads ownedByViewer and hasOwner from the owner registry")
    func anExternalViewerReadsTheOwnership() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer.external(
            owning: [tree.owned.id.ulidString], clientOwned: [tree.subagent.id.ulidString])

        let ownership = try await Self.ownership(of: [tree.owned, tree.subagent, tree.started], viewer: viewer, on: tree)

        #expect(ownership == [.ownedByViewer, .ownedByOtherClient, .noOwner])
    }

    /// A device of the user reads the same two fields from the owner
    /// registry, also for a session that it does not own.
    @Test("a device of the user reads ownedByViewer and hasOwner from the owner registry")
    func aUserDeviceReadsTheOwnership() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer(
            clientId: Self.deviceClientId, trust: .userDevice, ownedSessions: [tree.owned.id.ulidString],
            clientOwnedSessions: [tree.stranger.id.ulidString])

        let ownership = try await Self.ownership(of: [tree.owned, tree.stranger, tree.fork], viewer: viewer, on: tree)

        #expect(ownership == [.ownedByViewer, .ownedByOtherClient, .noOwner])
    }

    /// The agent, a call with no viewer, is no client and reads no owner
    /// registry: each session reads `ownedByViewer: false` and
    /// `hasOwner: false`.
    @Test("the agent reads ownedByViewer and hasOwner as false")
    func theAgentReadsNoOwnership() async throws {
        let tree = Tree()

        let ownership = try await Self.ownership(of: [tree.owned, tree.stranger], viewer: nil, on: tree)

        #expect(ownership == [.noOwner, .noOwner])
    }

    // MARK: - session(id:)

    /// `session(id:)` gives the facts of the directory: the tags sorted, and
    /// each enum in `UPPER_SNAKE`.
    @Test("session(id:) gives the facts of the session")
    func sessionGivesTheFacts() async throws {
        let tree = Tree()
        try tree.directory.finishTurn(of: tree.owned.id, lastSummary: Self.lastSummary)

        let session = try await Self.run(Self.sessionQuery, id: tree.owned.id.ulidString, on: tree.graph)
            .object("session")

        #expect(session["id"] as? String == tree.owned.id.ulidString)
        #expect(session["agentId"] as? String == Fixtures.agentID)
        #expect(session["agentName"] as? String == Fixtures.agentName)
        #expect(session["cwd"] as? String == Fixtures.workingFolder.path)
        #expect(session["title"] as? String == Self.ownedTitle)
        #expect(session["tags"] as? [String] == Self.ownedTags.sorted())
        #expect(session["kind"] as? String == "ROOT")
        #expect(session["state"] as? String == "IDLE")
        #expect(session["origin"] as? String == "CLIENT")
        #expect(session["lastSummary"] as? String == Self.lastSummary)
        #expect(session["isLive"] as? Bool == true)
        #expect(session["createdAt"] as? String == DateTime(Fixtures.fixedDate).rfc3339)
    }

    /// `session(id:)` reads an id in lower case, and gives it canonical.
    @Test("session(id:) reads an id in lower case")
    func sessionReadsALowerCaseID() async throws {
        let tree = Tree()

        let session = try await Self.run(
            Self.sessionQuery, id: tree.subagent.id.ulidString.lowercased(), on: tree.graph
        ).object("session")

        #expect(session["id"] as? String == tree.subagent.id.ulidString)
        #expect(session["kind"] as? String == "SUBAGENT")
    }

    /// `session(id:)` of an id that no session has is `null`, not an error.
    @Test("session(id:) of an unknown id is null")
    func anUnknownSessionIsNull() async throws {
        let tree = Tree()

        let reply = try await Self.run(Self.sessionQuery, id: ULID().ulidString, on: tree.graph)

        #expect(reply.codes.isEmpty)
        #expect(reply.isNull("session"))
    }

    /// `session(id:)` of a text that is not a session id gives
    /// `INVALID_SESSION_ID`, with the corrective of the tool.
    @Test("session(id:) of a text that is not a session id gives INVALID_SESSION_ID")
    func aMalformedIDGivesInvalidSessionID() async throws {
        let tree = Tree()

        let reply = try await Self.run(Self.sessionQuery, id: "not-a-session", on: tree.graph)

        #expect(reply.codes == ["INVALID_SESSION_ID"])
        #expect(reply.isNull("session"))
    }

    // MARK: - Relatives

    /// `parent` is the parent of a subagent, `startedBy` the session that
    /// started a root session, and `children` the subagents only: a fork is
    /// not a child.
    @Test("parent, startedBy and children link the sessions")
    func theRelativesLinkTheSessions() async throws {
        let tree = Tree()

        let owned = try await Self.run(Self.relativesQuery, id: tree.owned.id.ulidString, on: tree.graph)
            .object("session")
        let subagent = try await Self.run(Self.relativesQuery, id: tree.subagent.id.ulidString, on: tree.graph)
            .object("session")
        let started = try await Self.run(Self.relativesQuery, id: tree.started.id.ulidString, on: tree.graph)
            .object("session")

        #expect(owned["parent"] is NSNull)
        #expect(owned["startedBy"] is NSNull)
        #expect((owned["children"] as? [[String: Any]])?.map { $0["id"] as? String } == [tree.subagent.id.ulidString])
        #expect((subagent["parent"] as? [String: Any])?["id"] as? String == tree.owned.id.ulidString)
        #expect((started["startedBy"] as? [String: Any])?["id"] as? String == tree.owned.id.ulidString)
    }

    /// The parent or the starter of a session that an external viewer
    /// cannot see is `null`.
    @Test("a parent or a starter that the external viewer cannot see is null")
    func aHiddenRelativeIsNull() async throws {
        let tree = Tree()
        let viewer = GraphQLViewer.external(owning: [tree.subagent.id.ulidString, tree.started.id.ulidString])

        let subagent = try await Self.run(
            Self.relativesQuery, id: tree.subagent.id.ulidString, viewer: viewer, on: tree.graph)
        let started = try await Self.run(
            Self.relativesQuery, id: tree.started.id.ulidString, viewer: viewer, on: tree.graph)

        #expect(subagent.codes.isEmpty)
        #expect(try subagent.object("session")["parent"] is NSNull)
        #expect(try started.object("session")["startedBy"] is NSNull)
    }

    // MARK: - The filter

    /// With no limit, `sessions` gives at most 50 sessions: the default of
    /// the endpoint, not the default of `list sessions`.
    @Test("sessions gives at most 50 sessions with no limit")
    func sessionsHasADefaultLimitOf50() async throws {
        let directory = InMemorySessionDirectory()
        Self.registerSessions(Self.crowdSize, in: directory)

        let ids = try Self.ids(of: await Self.sessions(on: SessionsGraph.endpoint(of: directory)))

        #expect(ids.count == Self.defaultListLimit)
    }

    /// The `limit` of the filter cuts the list.
    @Test("the limit of the filter cuts the list")
    func theLimitCutsTheList() async throws {
        let tree = Tree()

        let filter: Map = ["limit": .number(Number(Self.smallLimit))]

        let ids = try Self.ids(of: await Self.sessions(filter: filter, on: tree.graph))

        #expect(ids.count == Self.smallLimit)
    }

    /// The `kind` and `parentId` of the filter match, and `parentId` reads an
    /// id in lower case.
    @Test("kind and parentId filter the sessions")
    func kindAndParentFilterTheSessions() async throws {
        let tree = Tree()
        let filter: Map = ["kind": "SUBAGENT", "parentId": .string(tree.owned.id.ulidString.lowercased())]

        let ids = try Self.ids(of: await Self.sessions(filter: filter, on: tree.graph))

        #expect(ids == [tree.subagent.id.ulidString])
    }

    /// The `startedById` of the filter finds the sessions that one session
    /// started.
    @Test("startedById finds the sessions that one session started")
    func startedByFiltersTheSessions() async throws {
        let tree = Tree()

        let ids = try Self.ids(
            of: await Self.sessions(filter: ["startedById": .string(tree.started.id.ulidString)], on: tree.graph))

        #expect(ids == [tree.startedByStarted.id.ulidString])
    }

    /// A `state` of `ARCHIVED` also finds the sessions that are not live,
    /// as `list sessions` does.
    @Test("state ARCHIVED finds the archived sessions, which are not live")
    func archivedStateFindsRecordedSessions() async throws {
        let tree = Tree()
        _ = try await tree.directory.archive(tree.stranger.id, by: .user(clientID: Self.deviceClientId))

        let ids = try Self.ids(of: await Self.sessions(filter: ["state": "ARCHIVED"], on: tree.graph))

        #expect(ids == [tree.stranger.id.ulidString])
    }

    /// A relative `cwd` gives `INVALID_FOLDER`, with the corrective of the
    /// tool.
    @Test("a relative cwd gives INVALID_FOLDER")
    func aRelativeFolderGivesInvalidFolder() async throws {
        let tree = Tree()

        let reply = try await Self.sessions(filter: ["cwd": "project"], on: tree.graph)

        #expect(reply.codes == ["INVALID_FOLDER"])
    }

    /// A `parentId` that is not a session id gives `INVALID_SESSION_ID`.
    @Test("a parentId that is not a session id gives INVALID_SESSION_ID")
    func aMalformedParentGivesInvalidSessionID() async throws {
        let tree = Tree()

        let reply = try await Self.sessions(filter: ["parentId": "not-a-session"], on: tree.graph)

        #expect(reply.codes == ["INVALID_SESSION_ID"])
    }

    // MARK: - inbox(sessionId:)

    /// `inbox` gives the unread messages of a session, the oldest first: a
    /// session sender as its session, and a user sender as its client id.
    @Test("inbox gives the unread messages, the oldest first, with their senders")
    func inboxGivesTheUnreadMessages() async throws {
        let tree = Tree()
        try await Self.send(Self.firstText, from: tree.started.id, to: tree.owned.id, in: tree.directory)
        try await Self.sendFromTheUser(Self.secondText, to: tree.owned.id, in: tree.directory)
        let stored = try await tree.directory.inbox(of: tree.owned.id, markRead: false)

        let messages = try await Self.inbox(of: tree.owned.id, on: tree.graph)

        #expect(messages.map { $0["text"] as? String } == [Self.firstText, Self.secondText])
        #expect(messages.map { $0["id"] as? String } == stored.map(\.id.description))
        #expect(messages.map { ($0["to"] as? [String: Any])?["id"] as? String } == stored.map(\.to.ulidString))
        #expect(messages.map { $0["isRead"] as? Bool } == [false, false])
        #expect(messages.map { $0["sentAt"] as? String } == stored.map { DateTime($0.sentAt).rfc3339 })
        #expect(messages.map { $0["chainDepth"] as? Int } == stored.map(\.chainDepth))
        #expect(messages.first?["inReplyTo"] is NSNull)
        let senders = messages.compactMap { $0["from"] as? [String: Any] }
        #expect((senders.first?["session"] as? [String: Any])?["id"] as? String == tree.started.id.ulidString)
        #expect(senders.first?["clientId"] is NSNull)
        #expect(senders.last?["session"] is NSNull)
        #expect(senders.last?["clientId"] as? String == Self.deviceClientId)
    }

    /// The `inbox` query does not mark the messages read (D72): a following
    /// `read inbox` op of the `sessions` tool still gives them.
    @Test("an inbox query leaves the messages unread, and read inbox still gives them")
    func inboxDoesNotMarkMessagesRead() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary()
        directory.register(sender)
        let tool = try SessionsTool(directory: directory)
        let graph = SessionsGraph.endpoint(of: directory)

        let (first, second, output) = try await Fixtures.asCaller(in: directory) { callerID in
            try await Self.send(Self.firstText, from: sender.id, to: callerID, in: directory)
            let first = try await Self.inbox(of: callerID, on: graph)
            let second = try await Self.inbox(of: callerID, on: graph)
            let output = try await tool.call(arguments: Fixtures.payload(Self.readInboxOp))
            return (first, second, output)
        }

        #expect(first.map { $0["text"] as? String } == [Self.firstText])
        #expect(first.map { $0["isRead"] as? Bool } == [false])
        #expect(second.map { $0["text"] as? String } == [Self.firstText])
        #expect(output.contains(Self.firstText), "output was: \(output)")
    }

    /// The `limit` of `inbox` keeps the oldest messages.
    @Test("the limit of inbox keeps the oldest messages")
    func theInboxLimitKeepsTheOldest() async throws {
        let tree = Tree()
        try await Self.sendFromTheUser(Self.firstText, to: tree.owned.id, in: tree.directory)
        try await Self.sendFromTheUser(Self.secondText, to: tree.owned.id, in: tree.directory)

        let reply = try await Self.run(
            Self.limitedInboxQuery, variables: ["id": .string(tree.owned.id.ulidString), "limit": 1], on: tree.graph)

        #expect(try reply.list("inbox").map { $0["text"] as? String } == [Self.firstText])
    }

    /// An external viewer gets no message of a session that it cannot see,
    /// and the sender of a message that it cannot see is `null`.
    @Test("an external viewer gets no message of a hidden session, and a hidden sender is null")
    func anExternalViewerGetsOnlyVisibleMessages() async throws {
        let tree = Tree()
        try await Self.send(Self.firstText, from: tree.stranger.id, to: tree.owned.id, in: tree.directory)
        try await Self.send(Self.secondText, from: tree.owned.id, to: tree.stranger.id, in: tree.directory)
        let viewer = GraphQLViewer.external(owning: [tree.owned.id.ulidString])

        let owned = try await Self.inbox(of: tree.owned.id, viewer: viewer, on: tree.graph)
        let hidden = try await Self.run(
            Self.inboxQuery, id: tree.stranger.id.ulidString, viewer: viewer, on: tree.graph)

        #expect(owned.map { $0["text"] as? String } == [Self.firstText])
        #expect((owned.first?["from"] as? [String: Any])?["session"] is NSNull)
        #expect(hidden.codes.isEmpty)
        #expect(try hidden.list("inbox").isEmpty)
    }

    /// `inbox` of an id that no session has is empty, and of a text that is
    /// not a session id gives `INVALID_SESSION_ID`.
    @Test("inbox of an unknown session is empty, and of a malformed id gives INVALID_SESSION_ID")
    func inboxOfAnUnknownSession() async throws {
        let tree = Tree()

        let unknown = try await Self.run(Self.inboxQuery, id: ULID().ulidString, on: tree.graph)
        let malformed = try await Self.run(Self.inboxQuery, id: "not-a-session", on: tree.graph)

        #expect(unknown.codes.isEmpty)
        #expect(try unknown.list("inbox").isEmpty)
        #expect(malformed.codes == ["INVALID_SESSION_ID"])
    }

    /// `unreadCount` counts the unread messages to a session, and marks none
    /// read.
    @Test("unreadCount counts the unread messages and marks none read")
    func unreadCountCountsTheUnreadMessages() async throws {
        let tree = Tree()
        let texts = [Self.firstText, Self.secondText]
        for text in texts {
            try await Self.sendFromTheUser(text, to: tree.owned.id, in: tree.directory)
        }

        let session = try await Self.run(Self.unreadQuery, id: tree.owned.id.ulidString, on: tree.graph)
            .object("session")

        #expect(session["unreadCount"] as? Int == texts.count)
        #expect(try await tree.directory.inbox(of: tree.owned.id, markRead: false).count == texts.count)
    }

    // MARK: - Aliases

    /// The alias tables take `sessionId` for the `id` of `session`, and
    /// `agent` and `folder` for `agentId` and `cwd`, and the response tells
    /// each rewrite in `extensions.rewrites`.
    @Test("the aliases of session work and show in extensions.rewrites")
    func theAliasesOfSessionWork() async throws {
        let tree = Tree()

        let reply = try await Self.run(
            "{ session(sessionId: \"\(tree.owned.id.ulidString)\") { agent folder } }", on: tree.graph)

        let session = try reply.object("session")
        #expect(session["agent"] as? String == Fixtures.agentID)
        #expect(session["folder"] as? String == Fixtures.workingFolder.path)
        #expect(reply.rewrote("sessionId", to: "id"))
        #expect(reply.rewrote("agent", to: "agentId"))
        #expect(reply.rewrote("folder", to: "cwd"))
    }

    /// The alias tables take `id` for the `sessionId` of `inbox`.
    @Test("the id alias of inbox works")
    func theIDAliasOfInboxWorks() async throws {
        let tree = Tree()
        try await Self.sendFromTheUser(Self.firstText, to: tree.owned.id, in: tree.directory)

        let reply = try await Self.run("{ inbox(id: \"\(tree.owned.id.ulidString)\") { text } }", on: tree.graph)

        #expect(try reply.list("inbox").map { $0["text"] as? String } == [Self.firstText])
        #expect(reply.rewrote("id", to: "sessionId"))
    }
}
