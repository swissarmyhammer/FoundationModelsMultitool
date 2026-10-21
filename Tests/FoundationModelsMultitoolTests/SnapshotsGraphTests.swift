// `SnapshotsGraphTests` — the behavioral suite of the `snapshots` GraphQL
// endpoint (MT-13, task `^x8vtywz`).
//
// Each test makes its own temporary git repository and its own
// `SnapshotStore` in a temporary folder outside the repository, and opens the
// session key on the store as `SnapshotHook` does on `SessionStart`. The
// endpoint then reads the same store through GraphQL. No test reads a clock or
// waits for time to pass.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import GraphQL
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `snapshots` GraphQL endpoint: the checkpoint
/// queries, the `rollbackTimeline` mutation, the viewer rules and the error
/// codes.
@Suite("SnapshotsGraphTests", .ownsTemporaryDirectories)
struct SnapshotsGraphTests {

    // MARK: - Constants

    /// The name of each temporary folder of a test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "SnapshotsGraphTests"

    /// The session ID of the session of a test, which the store reads as the
    /// owner.
    private static let sessionId = "session-one"

    /// The session key (the lineage key) that the stub resolver gives for
    /// ``sessionId``.
    private static let sessionKey = "lineage-one"

    /// A session ID that the stub resolver does not know.
    private static let unknownSessionId = "session-unknown"

    /// The ID of a client that is not a device of the user.
    private static let externalClientId = "client-external"

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// The file that the base commit holds.
    private static let baseFile = "base.txt"

    /// The file that the first checkpoint adds.
    private static let firstFile = "first.txt"

    /// The file that the second checkpoint adds.
    private static let secondFile = "second.txt"

    /// The file that another store adds after the two checkpoints.
    private static let thirdFile = "third.txt"

    /// The label of the first checkpoint.
    private static let firstLabel = "one"

    /// The tool call ID of the second checkpoint.
    private static let toolCallId = "call-7"

    /// The tool name of the second checkpoint.
    private static let toolName = "runCode"

    /// The index of the first checkpoint.
    private static let firstIndex = 1

    /// The index of the second checkpoint.
    private static let secondIndex = 2

    /// The index of the checkpoint after two checkpoints and one rollback.
    private static let rollbackIndex = 3

    /// An index that no checkpoint of a fixture has.
    private static let missingIndex = 9

    /// The name of the golden file of the schema, under
    /// `Tests/FoundationModelsMultitoolTests/Goldens`.
    private static let goldenFileName = "snapshots.graphql"

    /// The code of the toolkit for an id that the endpoint does not hold.
    private static let notFoundCode = GraphQLToolkitError.notFound(kind: "", id: "").code

    /// The root query of the newest cursor.
    private static let cursorQuery = "{ cursor }"

    /// The subscription of the `snapshotChanges` alias probe, after a cursor.
    private static let snapshotChangesSubscription =
        "subscription($after: String) { snapshotChanges(after: $after) { cursor added changed removed } }"

    /// Each error of the store, with the code that the endpoint gives for it.
    /// `unavailable` is the `NOT_FOUND` of the toolkit for the session.
    private static let storeErrorCodes: [(error: SnapshotError, code: String)] = [
        (.unavailable, notFoundCode),
        (.notAvailable(cause: .timelineConflict), "SNAPSHOTS_NOT_AVAILABLE"),
        (.noTimeline, "NO_TIMELINE"),
        (.invalidCheckpoint(index: missingIndex), "INVALID_CHECKPOINT"),
        (.workingDirectoryMismatch, "WORKING_DIRECTORY_MISMATCH"),
        (.timelineConflict, "CONFLICTING_TIMELINE"),
        (.unreadableTimeline, "UNREADABLE_TIMELINE"),
        (.sessionKeyOpen, "SESSION_KEY_OPEN"),
        (.invalidSessionKey, "INVALID_SESSION_KEY"),
        (.fileNotInCheckpoint(path: "README.md"), "FILE_NOT_IN_CHECKPOINT"),
    ]

    /// The selection of each checkpoint that a test reads.
    private static let checkpointSelection = "{ id index trigger toolCallId files at }"

    /// The `checkpoints` query of a session.
    private static let checkpointsQuery =
        "query($sessionId: ID!) { checkpoints(sessionId: $sessionId) \(checkpointSelection) }"

    /// The `checkpoint` query of one index of a session.
    private static let checkpointQuery =
        "query($sessionId: ID!, $index: Int!) { checkpoint(sessionId: $sessionId, index: $index) "
        + "\(checkpointSelection) }"

    /// The `rollbackTimeline` mutation.
    private static let rollbackMutation =
        "mutation($input: RollbackTimelineInput!) { rollbackTimeline(input: $input) \(checkpointSelection) }"

    // MARK: - Helpers

    /// One open session key over one temporary repository, and the endpoint
    /// over its store.
    private struct Fixture {

        /// The repository whose work tree the store records.
        let repository: TemporaryGitRepository

        /// The folder that holds the shadow repositories of ``store``.
        let storeDirectory: URL

        /// The store that the endpoint and the test share.
        let store: SnapshotStore

        /// The endpoint over ``store``.
        let graph: SnapshotsGraph
    }

    /// The stub resolver: it gives ``sessionKey`` for ``sessionId``, and no
    /// key for each other session ID.
    ///
    /// - Parameter id: The session ID.
    /// - Returns: The session key, or `nil`.
    @Sendable private static func stubSessionKey(_ id: String) async -> String? {
        id == sessionId ? sessionKey : nil
    }

    /// The inverse of ``stubSessionKey(_:)``: it gives ``sessionId`` for
    /// ``sessionKey``, and no session ID for each other key.
    ///
    /// - Parameter key: The session key.
    /// - Returns: The session ID, or `nil`.
    @Sendable private static func stubSessionId(_ key: String) async -> String? {
        key == sessionKey ? sessionId : nil
    }

    /// Makes a repository with one base commit, a store, the session key
    /// open on the store for ``sessionId``, and the endpoint over the store.
    ///
    /// - Parameters:
    ///   - key: The session key that the store opens for ``sessionId``.
    ///   - resolver: The session-key resolver of the endpoint.
    /// - Returns: The fixture.
    /// - Throws: What the repository or the store throws.
    private static func makeFixture(
        key: String = sessionKey,
        resolver: @escaping @Sendable (String) async -> String? = stubSessionKey
    ) async throws -> Fixture {
        let repository = try TemporaryGitRepository()
        try repository.write("base\n", to: baseFile)
        _ = try repository.commit(message: "base")
        let storeDirectory = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let store = SnapshotStore(directory: storeDirectory)
        try await store.open(sessionKey: key, owner: sessionId, workingDirectory: repository.workDirectory)
        return Fixture(
            repository: repository, storeDirectory: storeDirectory, store: store,
            graph: SnapshotsGraph(store: store, sessionKey: resolver, sessionId: stubSessionId))
    }

    /// Makes two checkpoints in the fixture: a manual one that adds
    /// ``firstFile``, and a tool one that adds ``secondFile``.
    ///
    /// - Parameters:
    ///   - fixture: The fixture whose work tree changes.
    ///   - key: The session key of the fixture.
    /// - Throws: What the repository or the store throws.
    private static func makeTwoCheckpoints(in fixture: Fixture, key: String = sessionKey) async throws {
        try fixture.repository.write("one\n", to: firstFile)
        _ = try await fixture.store.take(sessionKey: key, owner: sessionId, trigger: .manual(label: firstLabel))
        try fixture.repository.write("two\n", to: secondFile)
        _ = try await fixture.store.take(
            sessionKey: key, owner: sessionId, trigger: .toolUse(toolCallID: toolCallId, toolName: toolName))
    }

    /// Makes a fixture, reads the cursor of its endpoint, and then takes the
    /// first checkpoint, which adds ``firstFile``.
    ///
    /// - Returns: The fixture, and the cursor from before the checkpoint.
    /// - Throws: What the repository, the store or the endpoint throws, or an
    ///   error when the response has no cursor.
    private static func checkpointAfterCursor() async throws -> (fixture: Fixture, cursor: String) {
        let fixture = try await makeFixture()
        let cursor = try #require(try await run(cursorQuery, on: fixture.graph).data?["cursor"] as? String)
        try fixture.repository.write("one\n", to: firstFile)
        _ = try await fixture.store.take(
            sessionKey: sessionKey, owner: sessionId, trigger: .manual(label: firstLabel))
        return (fixture, cursor)
    }

    /// Runs one document on the endpoint of `fixture`.
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
        _ query: String, variables: [String: Map] = [:], viewer: GraphQLViewer? = nil, on graph: SnapshotsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await graph.execute(query: query, variables: variables, operationName: nil, viewer: viewer))
    }

    /// Runs the `checkpoints` query of `id`.
    ///
    /// - Parameters:
    ///   - id: The session ID.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws.
    private static func checkpoints(
        of id: String = sessionId, viewer: GraphQLViewer? = nil, on graph: SnapshotsGraph
    ) async throws -> GraphQLReply {
        try await run(checkpointsQuery, variables: ["sessionId": .string(id)], viewer: viewer, on: graph)
    }

    /// Runs the `checkpoint` query of `index` of `id`.
    ///
    /// - Parameters:
    ///   - index: The index of the checkpoint.
    ///   - id: The session ID.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws.
    private static func checkpoint(
        _ index: Int, of id: String = sessionId, viewer: GraphQLViewer? = nil, on graph: SnapshotsGraph
    ) async throws -> GraphQLReply {
        try await run(
            checkpointQuery, variables: ["sessionId": .string(id), "index": .number(Number(index))], viewer: viewer,
            on: graph)
    }

    /// Runs the `rollbackTimeline` mutation to `index` of `id`.
    ///
    /// - Parameters:
    ///   - index: The index of the checkpoint to restore.
    ///   - id: The session ID.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws.
    private static func rollback(
        to index: Int, of id: String = sessionId, viewer: GraphQLViewer? = nil, on graph: SnapshotsGraph
    ) async throws -> GraphQLReply {
        let input: Map = ["sessionId": .string(id), "index": .number(Number(index))]
        return try await run(rollbackMutation, variables: ["input": input], viewer: viewer, on: graph)
    }

    /// A client that is not a device of the user, and that owns `owned`.
    ///
    /// - Parameter owned: The session IDs that the client owns.
    /// - Returns: The viewer.
    private static func externalViewer(owning owned: Set<String> = []) -> GraphQLViewer {
        GraphQLViewer(clientId: externalClientId, trust: .external, ownedSessions: owned)
    }

    /// The text of `.toolUse` as the `trigger` field gives it.
    private static var toolTrigger: String {
        SnapshotCheckpoint.text(of: .toolUse(toolCallID: toolCallId, toolName: toolName))
    }

    // MARK: - The endpoint contract

    /// The endpoint has the name `snapshots`, the version `1` and the server
    /// scope.
    @Test("the endpoint is snapshots, version 1, with the server scope")
    func theEndpointFacts() async throws {
        let fixture = try await Self.makeFixture()

        #expect(fixture.graph.name == "snapshots")
        #expect(fixture.graph.version == "1")
        #expect(fixture.graph.scope == .server)
    }

    /// The endpoint conforms to the toolkit conventions, rule 9 among them.
    /// The `listCheckpoints` probe checks that its response reports the
    /// rewrite to `checkpoints` and has no error. The `snapshotChanges` probe
    /// resumes after the cursor that the endpoint gave before one checkpoint
    /// was taken, and checks that its first response reports the rewrite to
    /// `changes` and has no error;
    /// ``theFirstSnapshotChangesResponseAddsTheCheckpoint()`` checks its data.
    @Test("the endpoint conforms, with the listCheckpoints and snapshotChanges alias probes")
    func theEndpointConforms() async throws {
        let setup = try await Self.checkpointAfterCursor()
        let probes = [
            GraphQLAliasProbe(
                query: "{ listCheckpoints(sessionId: \"\(Self.sessionId)\") { id } }",
                from: "listCheckpoints", to: "checkpoints"),
            GraphQLAliasProbe(
                query: Self.snapshotChangesSubscription, variables: ["after": .string(setup.cursor)],
                from: "snapshotChanges", to: "changes", kind: .subscription),
        ]
        let codes = Self.storeErrorCodes.map(\.code)

        let problems = await GraphQLEndpointConformance.problems(
            of: setup.fixture.graph, scope: .server, probes: probes, codes: codes, clock: ManualRunClock())

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    /// The first response of the subscription of the `snapshotChanges`
    /// probe, after the same cursor, is the change of the checkpoint taken
    /// after that cursor: `added` holds its id, and `changed` and `removed`
    /// are empty.
    @Test("the first response of the snapshotChanges probe subscription adds the checkpoint")
    func theFirstSnapshotChangesResponseAddsTheCheckpoint() async throws {
        let setup = try await Self.checkpointAfterCursor()
        var responses = try await setup.fixture.graph.subscribe(
            query: Self.snapshotChangesSubscription, variables: ["after": .string(setup.cursor)],
            operationName: nil, viewer: nil
        ).makeAsyncIterator()

        let reply = try GraphQLReply(json: try #require(try await responses.next()))

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let change = try reply.object("snapshotChanges")
        #expect(change["added"] as? [String] == ["\(Self.sessionId):\(Self.firstIndex)"])
        #expect(change["changed"] as? [String] == [])
        #expect(change["removed"] as? [String] == [])
    }

    /// Each type, field, argument and input field of the schema has a
    /// description, because a client learns the schema with introspection.
    @Test("each part of the schema has a description")
    func eachPartOfTheSchemaHasADescription() async throws {
        let fixture = try await Self.makeFixture()

        let undescribed = try GraphQLSchemaDescriptions.undescribed(in: buildSchema(source: fixture.graph.schema))

        #expect(undescribed.isEmpty, "undescribed: \(undescribed)")
    }

    /// The SDL schema is the schema in the golden file.
    @Test("the schema matches the golden file")
    func theSchemaMatchesTheGoldenFile() async throws {
        let fixture = try await Self.makeFixture()
        let goldenFile = RepositoryFile.root
            .appendingPathComponent("Tests/FoundationModelsMultitoolTests/Goldens")
            .appendingPathComponent(Self.goldenFileName)

        let problems = GraphQLSchemaGolden.problems(of: fixture.graph.schema, against: goldenFile)

        #expect(problems.isEmpty, "problems: \(problems)")
    }

    /// A registered snapshots capability gives its `snapshots` endpoint
    /// through `MultiTool.graphQLEndpoints`.
    @Test("MultiTool gives the snapshots endpoint of a registered snapshots capability")
    func multiToolGivesTheSnapshotsEndpoint() throws {
        let store = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName))
        let registry = try MultiTool.Builder().withCapability(SnapshotsCapability(store: store)).buildRegistry()

        let names = MultiTool(registry: registry).graphQLEndpoints.map(\.name)

        #expect(names == [SnapshotsGraph.endpointName])
    }

    // MARK: - Queries

    /// `checkpoints` gives each checkpoint of the timeline, oldest first,
    /// with its index, trigger, files and date.
    @Test("checkpoints gives the timeline of the session, oldest first")
    func checkpointsGivesTheTimeline() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        let stored = try await fixture.store.checkpoints(sessionKey: Self.sessionKey, owner: Self.sessionId)

        let checkpoints = try await Self.checkpoints(on: fixture.graph).list("checkpoints")

        #expect(checkpoints.map { $0["index"] as? Int } == [Self.firstIndex, Self.secondIndex])
        #expect(checkpoints.map { $0["trigger"] as? String } == ["label \(Self.firstLabel)", Self.toolTrigger])
        #expect(checkpoints.map { $0["files"] as? [String] } == [[Self.firstFile], [Self.secondFile]])
        #expect(checkpoints.map { $0["at"] as? String } == stored.map { DateTime($0.date).rfc3339 })
    }

    /// The `toolCallId` of a checkpoint is the tool call of a tool trigger,
    /// and `null` for each other trigger.
    @Test("toolCallId is the tool call of a tool trigger, and null for a manual one")
    func toolCallIdIsTheToolCall() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let checkpoints = try await Self.checkpoints(on: fixture.graph).list("checkpoints")

        #expect(checkpoints.first?["toolCallId"] is NSNull)
        #expect(checkpoints.last?["toolCallId"] as? String == Self.toolCallId)
    }

    /// The `id` of a checkpoint is `<sessionId>:<index>`, the same in the
    /// list and in the query of one checkpoint.
    @Test("the id of a checkpoint is <sessionId>:<index>")
    func theIdIsTheSessionIdAndTheIndex() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let listed = try await Self.checkpoints(on: fixture.graph).list("checkpoints").map { $0["id"] as? String }
        let single = try await Self.checkpoint(Self.secondIndex, on: fixture.graph).object("checkpoint")

        #expect(listed == ["\(Self.sessionId):\(Self.firstIndex)", "\(Self.sessionId):\(Self.secondIndex)"])
        #expect(single["id"] as? String == "\(Self.sessionId):\(Self.secondIndex)")
    }

    /// `checkpoint` gives the checkpoint of one index.
    @Test("checkpoint gives the checkpoint of one index")
    func checkpointGivesOneCheckpoint() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let checkpoint = try await Self.checkpoint(Self.firstIndex, on: fixture.graph).object("checkpoint")

        #expect(checkpoint["index"] as? Int == Self.firstIndex)
        #expect(checkpoint["files"] as? [String] == [Self.firstFile])
    }

    /// `checkpoint` gives `null` for an index that no checkpoint has.
    @Test("checkpoint gives null for an unknown index")
    func anUnknownIndexGivesNull() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let reply = try await Self.checkpoint(Self.missingIndex, on: fixture.graph)

        #expect(reply.codes.isEmpty)
        #expect(reply.isNull("checkpoint"))
    }

    /// The endpoint reads the timeline of the session key that the resolver
    /// gives for the session ID, with the session ID as the owner.
    @Test("a stub resolver maps the session id to its session key")
    func theResolverMapsTheSessionIdToItsKey() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let byId = try await Self.checkpoints(of: Self.sessionId, on: fixture.graph).list("checkpoints")
        let byKey = try await Self.checkpoints(of: Self.sessionKey, on: fixture.graph).list("checkpoints")

        #expect(byId.count == Self.secondIndex)
        #expect(byKey.isEmpty)
    }

    /// The capability's default resolver reads the session ID as the session
    /// key.
    @Test("the default resolver of the capability treats the session id as the key")
    func theDefaultResolverTreatsTheSessionIdAsTheKey() async throws {
        let fixture = try await Self.makeFixture(key: Self.sessionId)
        try await Self.makeTwoCheckpoints(in: fixture, key: Self.sessionId)
        let graph = try #require(SnapshotsCapability(store: fixture.store).graphQLEndpoints.first as? SnapshotsGraph)

        let checkpoints = try await Self.checkpoints(on: graph).list("checkpoints")

        #expect(checkpoints.map { $0["index"] as? Int } == [Self.firstIndex, Self.secondIndex])
    }

    // MARK: - Mutation

    /// `rollbackTimeline` restores the work tree and gives the new rollback
    /// checkpoint at the end of the timeline.
    @Test("rollbackTimeline gives the new rollback checkpoint")
    func rollbackTimelineGivesTheNewCheckpoint() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let reply = try await Self.rollback(to: Self.firstIndex, on: fixture.graph)

        let checkpoint = try reply.object("rollbackTimeline")
        #expect(checkpoint["index"] as? Int == Self.rollbackIndex)
        #expect(checkpoint["id"] as? String == "\(Self.sessionId):\(Self.rollbackIndex)")
        #expect(checkpoint["trigger"] as? String == SnapshotCheckpoint.text(of: .rollback(to: Self.firstIndex)))
        #expect(checkpoint["files"] as? [String] == [Self.secondFile])
        let secondPath = fixture.repository.workDirectory.appendingPathComponent(Self.secondFile).path
        #expect(!FileManager.default.fileExists(atPath: secondPath))
    }

    /// `rollbackTimeline` gives `null` when the work tree already equals the
    /// checkpoint, and adds no checkpoint.
    @Test("rollbackTimeline gives null when the work tree already equals the checkpoint")
    func rollbackToTheCurrentStateGivesNull() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let reply = try await Self.rollback(to: Self.secondIndex, on: fixture.graph)

        #expect(reply.codes.isEmpty)
        #expect(reply.isNull("rollbackTimeline"))
    }

    /// `rollback` is an alias of `rollbackTimeline`, and the response tells
    /// the rewrite in `extensions.rewrites`.
    @Test("rollback works through the alias and shows in extensions.rewrites")
    func theRollbackAliasWorks() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let reply = try await Self.run(
            "mutation { rollback(input: {sessionId: \"\(Self.sessionId)\", index: \(Self.firstIndex)}) { index } }",
            on: fixture.graph)

        #expect(try reply.object("rollback")["index"] as? Int == Self.rollbackIndex)
        #expect(reply.rewrote("rollback", to: "rollbackTimeline"))
    }

    /// A rollback to an index that the timeline does not have gives
    /// `INVALID_CHECKPOINT`.
    @Test("rollbackTimeline to an unknown index gives INVALID_CHECKPOINT")
    func rollbackToAnUnknownIndexGivesInvalidCheckpoint() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let reply = try await Self.rollback(to: Self.missingIndex, on: fixture.graph)

        #expect(reply.codes == ["INVALID_CHECKPOINT"])
        #expect(reply.isNull("rollbackTimeline"))
    }

    /// After another store moved the timeline of the key, a rollback gives
    /// `CONFLICTING_TIMELINE`, and each later query of the session gives
    /// `SNAPSHOTS_NOT_AVAILABLE`.
    @Test("a timeline conflict gives CONFLICTING_TIMELINE, then SNAPSHOTS_NOT_AVAILABLE")
    func aTimelineConflictGivesItsCodes() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        let otherStore = try await Self.storeOnTheSameDirectory(as: fixture)
        try fixture.repository.write("three\n", to: Self.thirdFile)
        _ = try await otherStore.take(
            sessionKey: Self.sessionKey, owner: Self.unknownSessionId, trigger: .manual(label: nil))

        let rollback = try await Self.rollback(to: Self.firstIndex, on: fixture.graph)
        let query = try await Self.checkpoints(on: fixture.graph)

        #expect(rollback.codes == ["CONFLICTING_TIMELINE"])
        #expect(query.codes == ["SNAPSHOTS_NOT_AVAILABLE"])
    }

    // MARK: - Unknown and released sessions

    /// A session ID that the resolver does not know gives no checkpoints, a
    /// `null` checkpoint, and `NOT_FOUND` for a rollback.
    @Test("an unknown session gives [], null and NOT_FOUND")
    func anUnknownSessionGivesNothing() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)

        let list = try await Self.checkpoints(of: Self.unknownSessionId, on: fixture.graph)
        let single = try await Self.checkpoint(Self.firstIndex, of: Self.unknownSessionId, on: fixture.graph)
        let rollback = try await Self.rollback(to: Self.firstIndex, of: Self.unknownSessionId, on: fixture.graph)

        #expect(try list.list("checkpoints").isEmpty)
        #expect(single.isNull("checkpoint"))
        #expect(rollback.codes == [Self.notFoundCode])
    }

    /// A session that released its key gives no checkpoints, a `null`
    /// checkpoint, and `NOT_FOUND` for a rollback.
    @Test("a released session gives [], null and NOT_FOUND")
    func aReleasedSessionGivesNothing() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        await fixture.store.release(sessionKey: Self.sessionKey, owner: Self.sessionId)

        let list = try await Self.checkpoints(on: fixture.graph)
        let single = try await Self.checkpoint(Self.firstIndex, on: fixture.graph)
        let rollback = try await Self.rollback(to: Self.firstIndex, on: fixture.graph)

        #expect(try list.list("checkpoints").isEmpty)
        #expect(single.isNull("checkpoint"))
        #expect(rollback.codes == [Self.notFoundCode])
    }

    // MARK: - Viewers

    /// An external client that does not own the session sees no checkpoint,
    /// and its rollback gives `NOT_FOUND` and restores nothing.
    @Test("an external viewer cannot see or roll back a session it does not own")
    func anExternalViewerSeesOnlyItsOwnSessions() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        let viewer = Self.externalViewer()

        let list = try await Self.checkpoints(viewer: viewer, on: fixture.graph)
        let single = try await Self.checkpoint(Self.firstIndex, viewer: viewer, on: fixture.graph)
        let rollback = try await Self.rollback(to: Self.firstIndex, viewer: viewer, on: fixture.graph)

        #expect(try list.list("checkpoints").isEmpty)
        #expect(single.isNull("checkpoint"))
        #expect(rollback.codes == [Self.notFoundCode])
        let stored = try await fixture.store.checkpoints(sessionKey: Self.sessionKey, owner: Self.sessionId)
        #expect(stored.count == Self.secondIndex)
    }

    /// An external client that owns the session sees its checkpoints and can
    /// roll it back.
    @Test("an external viewer sees and rolls back a session it owns")
    func anExternalOwnerSeesItsSession() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        let viewer = Self.externalViewer(owning: [Self.sessionId])

        let list = try await Self.checkpoints(viewer: viewer, on: fixture.graph).list("checkpoints")
        let rollback = try await Self.rollback(to: Self.firstIndex, viewer: viewer, on: fixture.graph)

        #expect(list.count == Self.secondIndex)
        #expect(try rollback.object("rollbackTimeline")["index"] as? Int == Self.rollbackIndex)
    }

    /// A device of the user sees each session, also one it does not own.
    @Test("a user device sees each session")
    func aUserDeviceSeesEachSession() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeTwoCheckpoints(in: fixture)
        let viewer = GraphQLViewer(clientId: Self.deviceClientId, trust: .userDevice)

        let list = try await Self.checkpoints(viewer: viewer, on: fixture.graph).list("checkpoints")

        #expect(list.count == Self.secondIndex)
    }

    // MARK: - Error codes

    /// Each store error has an `UPPER_SNAKE` code, and `unavailable` is the
    /// `NOT_FOUND` of the toolkit for the session.
    @Test("each store error maps to its code", arguments: Self.storeErrorCodes)
    func eachStoreErrorMapsToItsCode(error: SnapshotError, code: String) {
        let coded = SnapshotsGraphError.coded(error, sessionId: Self.sessionId)

        #expect(coded.code == code)
        #expect(!coded.message.isEmpty)
    }

    /// Opens the key of `fixture` on a second store over the same store
    /// folder, for ``unknownSessionId``.
    ///
    /// - Parameter fixture: The fixture whose key the second store opens.
    /// - Returns: The second store.
    /// - Throws: What the store throws.
    private static func storeOnTheSameDirectory(as fixture: Fixture) async throws -> SnapshotStore {
        let store = SnapshotStore(directory: fixture.storeDirectory)
        try await store.open(
            sessionKey: sessionKey, owner: unknownSessionId, workingDirectory: fixture.repository.workDirectory)
        return store
    }
}
