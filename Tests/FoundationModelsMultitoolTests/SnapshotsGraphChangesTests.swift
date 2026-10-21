// `SnapshotsGraphChangesTests` — the behavioral suite of the `changes(after:)`
// subscription and the root `cursor` query of the `snapshots` GraphQL endpoint
// (MT-13, task `^mts9mtv`).
//
// Each case makes its own temporary git repository and its own `SnapshotStore`
// in a temporary folder, and opens two session keys on the store as
// `SnapshotHook` does on `SessionStart`. A case reads the changes in order
// from a subscription, and proves that one action gave one change by the
// change of a later marker checkpoint. No case reads a clock.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import GraphQL
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `changes(after:)` subscription of the `snapshots`
/// endpoint: the change of each checkpoint, the cursor, the resync, the
/// alias, the one change log of a store, and the filters of a subscription.
@Suite("SnapshotsGraphChangesTests", .ownsTemporaryDirectories, .timeLimit(.minutes(1)))
struct SnapshotsGraphChangesTests {

    // MARK: - Constants

    /// The name of each temporary folder of a test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "SnapshotsGraphChangesTests"

    /// The session ID of the first session of a test.
    private static let firstSessionId = "session-one"

    /// The session key that the stub resolver gives for ``firstSessionId``.
    private static let firstSessionKey = "lineage-one"

    /// The session ID of the second session of a test.
    private static let secondSessionId = "session-two"

    /// The session key that the stub resolver gives for ``secondSessionId``.
    private static let secondSessionKey = "lineage-two"

    /// A session key that the stub resolver does not know.
    private static let unknownSessionKey = "lineage-unknown"

    /// The owner of ``unknownSessionKey`` on the store.
    private static let unknownSessionId = "session-unknown"

    /// The ID of a client that is not a device of the user.
    private static let externalClientId = "client-external"

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// A device of the user, which sees each session.
    private static let deviceViewer = GraphQLViewer(clientId: deviceClientId, trust: .userDevice)

    /// The file that the base commit holds.
    private static let baseFile = "base.txt"

    /// The index of the first checkpoint of a session.
    private static let firstIndex = 1

    /// The capacity of the change log of a resync case: one change.
    private static let smallCapacity = 1

    /// The subscription of each case, with every field of a change.
    private static let changesDocument =
        "subscription($after: String, $sessionId: ID) { changes(after: $after, sessionId: $sessionId) "
        + "{ cursor at sessionId added changed removed } }"

    /// The subscription with the alias `snapshotChanges` of `changes`.
    private static let aliasDocument =
        "subscription($after: String) { snapshotChanges(after: $after) { cursor sessionId added changed removed } }"

    /// The root query of the newest cursor.
    private static let cursorQuery = "{ cursor }"

    /// The `checkpoint` query of one index of a session.
    private static let checkpointQuery =
        "query($sessionId: ID!, $index: Int!) { checkpoint(sessionId: $sessionId, index: $index) { id } }"

    /// The `rollbackTimeline` mutation.
    private static let rollbackMutation =
        "mutation($input: RollbackTimelineInput!) { rollbackTimeline(input: $input) { id } }"

    /// The code of a subscription that cannot resume with no gap.
    private static let resyncRequired = "RESYNC_REQUIRED"

    /// The text between the epoch and the sequence number of a cursor.
    private static let cursorSeparator: Character = ":"

    // MARK: - Helpers

    /// One change of a response of the subscription.
    struct Change: Equatable {
        /// The cursor that resumes after the change.
        let cursor: String

        /// The session whose timeline changed.
        let sessionId: String

        /// The ids that the change added.
        let added: [String]

        /// The ids that the change changed.
        let changed: [String]

        /// The ids that the change removed.
        let removed: [String]
    }

    /// The responses of one subscription, read in order.
    struct Subscription {
        /// The iterator of the responses.
        var responses: AsyncThrowingStream<String, Error>.AsyncIterator

        /// Reads the next response.
        ///
        /// - Returns: The response.
        /// - Throws: The error that ends the stream, or an error when the
        ///   stream ends or the response is not a JSON object.
        mutating func nextReply() async throws -> GraphQLReply {
            try GraphQLReply(json: try #require(try await responses.next()))
        }

        /// Reads the next change at the response key `key`.
        ///
        /// - Parameter key: The response key: `changes`, or the alias that
        ///   the document wrote.
        /// - Returns: The change.
        /// - Throws: An error when the response has no change at `key`.
        mutating func nextChange(at key: String = "changes") async throws -> Change {
            let reply = try await nextReply()
            #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
            let change = try reply.object(key)
            return Change(
                cursor: try #require(change["cursor"] as? String),
                sessionId: try #require(change["sessionId"] as? String),
                added: try #require(change["added"] as? [String]),
                changed: try #require(change["changed"] as? [String]),
                removed: try #require(change["removed"] as? [String]))
        }

        /// Reads each response until the stream ends.
        ///
        /// - Returns: The responses.
        /// - Throws: The error that ends the stream, or an error when a
        ///   response is not a JSON object.
        mutating func remainingReplies() async throws -> [GraphQLReply] {
            var replies: [GraphQLReply] = []
            while let json = try await responses.next() {
                replies.append(try GraphQLReply(json: json))
            }
            return replies
        }
    }

    /// Two open session keys over one temporary repository, and the store
    /// that holds them.
    struct Fixture {
        /// The repository whose work tree the store records.
        let repository: TemporaryGitRepository

        /// The store of the test.
        let store: SnapshotStore

        /// Makes a repository with one base commit, a store, and the keys of
        /// ``firstSessionId`` and ``secondSessionId`` open on it.
        ///
        /// - Parameter keys: The session key of each session, by session ID.
        /// - Throws: What the repository or the store throws.
        init(keys: [String: String] = stubKeys) async throws {
            repository = try TemporaryGitRepository()
            try repository.write("base\n", to: baseFile)
            _ = try repository.commit(message: "base")
            store = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: testDirectoryName))
            for (owner, key) in keys {
                try await store.open(sessionKey: key, owner: owner, workingDirectory: repository.workDirectory)
            }
        }

        /// Changes the work tree, and takes a manual checkpoint of a session.
        ///
        /// - Parameters:
        ///   - owner: The session ID.
        ///   - key: The session key of the session.
        /// - Returns: The index of the new checkpoint.
        /// - Throws: What the repository or the store throws, or an error when
        ///   the store makes no checkpoint.
        @discardableResult
        func take(owner: String, key: String) async throws -> Int {
            try repository.write("\(UUID().uuidString)\n", to: "\(UUID().uuidString).txt")
            let checkpoint = try await store.take(sessionKey: key, owner: owner, trigger: .manual(label: nil))
            return try #require(checkpoint).index
        }

        /// Takes a manual checkpoint of the first session.
        ///
        /// - Returns: The index of the new checkpoint.
        /// - Throws: What ``take(owner:key:)`` throws.
        @discardableResult
        func takeFirst() async throws -> Int {
            try await take(owner: firstSessionId, key: firstSessionKey)
        }

        /// Takes a manual checkpoint of the second session.
        ///
        /// - Returns: The index of the new checkpoint.
        /// - Throws: What ``take(owner:key:)`` throws.
        @discardableResult
        func takeSecond() async throws -> Int {
            try await take(owner: secondSessionId, key: secondSessionKey)
        }
    }

    /// The session key of each session of the stub resolvers, by session ID.
    private static let stubKeys = [firstSessionId: firstSessionKey, secondSessionId: secondSessionKey]

    /// The stub resolver: the session key of a session ID, or `nil`.
    ///
    /// - Parameter id: The session ID.
    /// - Returns: The session key, or `nil` for an unknown session ID.
    @Sendable private static func stubSessionKey(_ id: String) async -> String? {
        stubKeys[id]
    }

    /// The inverse of ``stubSessionKey(_:)``: the session ID of a session
    /// key, or `nil`.
    ///
    /// - Parameter key: The session key.
    /// - Returns: The session ID, or `nil` for an unknown session key.
    @Sendable private static func stubSessionId(_ key: String) async -> String? {
        stubKeys.first { $0.value == key }?.key
    }

    /// The endpoint over the store of `fixture`, with the stub resolvers.
    ///
    /// - Parameters:
    ///   - fixture: The fixture.
    ///   - capacity: The capacity of the change log of the store.
    /// - Returns: The endpoint.
    private static func graph(
        of fixture: Fixture, capacity: Int = SnapshotsGraph.changeLogCapacity
    ) -> SnapshotsGraph {
        SnapshotsGraph(
            store: fixture.store, sessionKey: stubSessionKey, sessionId: stubSessionId, changeLogCapacity: capacity)
    }

    /// Runs one document on `graph`.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - variables: The values of the variables.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    private static func run(
        _ document: String, variables: [String: Map] = [:], on graph: SnapshotsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await graph.execute(query: document, variables: variables, operationName: nil, viewer: deviceViewer))
    }

    /// The newest cursor of `graph`, from the root query `cursor`.
    ///
    /// - Parameter graph: The endpoint.
    /// - Returns: The cursor.
    /// - Throws: An error when the response has no cursor.
    private static func cursor(of graph: SnapshotsGraph) async throws -> String {
        try #require(try await run(cursorQuery, on: graph).data?["cursor"] as? String)
    }

    /// The `id` of one checkpoint, from the query `checkpoint`.
    ///
    /// - Parameters:
    ///   - index: The index of the checkpoint.
    ///   - sessionId: The session ID.
    ///   - graph: The endpoint.
    /// - Returns: The id.
    /// - Throws: An error when the response has no checkpoint.
    private static func checkpointId(
        _ index: Int, of sessionId: String = firstSessionId, on graph: SnapshotsGraph
    ) async throws -> String {
        let variables: [String: Map] = ["sessionId": .string(sessionId), "index": .number(Number(index))]
        let reply = try await run(checkpointQuery, variables: variables, on: graph)
        return try #require(try reply.object("checkpoint")["id"] as? String)
    }

    /// Starts a subscription on `graph`.
    ///
    /// - Parameters:
    ///   - graph: The endpoint.
    ///   - cursor: The cursor to resume after.
    ///   - sessionId: The session whose changes the subscription asks for, or
    ///     `nil` for each session.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - document: The subscription document, with the variable `$after`.
    /// - Returns: The subscription.
    /// - Throws: What the endpoint throws.
    private static func subscribe(
        to graph: SnapshotsGraph, after cursor: String, sessionId: String? = nil,
        viewer: GraphQLViewer? = deviceViewer, document: String = changesDocument
    ) async throws -> Subscription {
        var variables: [String: Map] = ["after": .string(cursor)]
        variables["sessionId"] = sessionId.map(Map.string)
        let stream = try await graph.subscribe(
            query: document, variables: variables, operationName: nil, viewer: viewer)
        return Subscription(responses: stream.makeAsyncIterator())
    }

    /// The sequence number of a cursor, the part after its epoch.
    ///
    /// - Parameter cursor: The cursor.
    /// - Returns: The sequence number.
    /// - Throws: An error when the cursor has no sequence number.
    private static func sequence(of cursor: String) throws -> UInt64 {
        try #require(cursor.split(separator: cursorSeparator).last.flatMap { UInt64($0) })
    }

    /// The change of one new checkpoint that a case expects.
    ///
    /// - Parameters:
    ///   - cursor: The cursor of the change, as the response gave it.
    ///   - sessionId: The session of the checkpoint.
    ///   - id: The id of the checkpoint.
    /// - Returns: The change.
    private static func added(cursor: String, sessionId: String = firstSessionId, id: String) -> Change {
        Change(cursor: cursor, sessionId: sessionId, added: [id], changed: [], removed: [])
    }

    /// A client that is not a device of the user, and that owns `owned`.
    ///
    /// - Parameter owned: The session ID that the client owns.
    /// - Returns: The viewer.
    private static func externalViewer(owning owned: String) -> GraphQLViewer {
        GraphQLViewer(clientId: externalClientId, trust: .external, ownedSessions: [owned])
    }

    // MARK: - The change of each checkpoint

    /// One action on the first session that makes one checkpoint.
    struct ActionCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let name: String

        /// Makes the checkpoint through the endpoint or the store.
        let act: @Sendable (Fixture, SnapshotsGraph) async throws -> Void

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// A take on the store, and a rollback through the endpoint.
    static let actionCases: [ActionCase] = [
        ActionCase(name: "take") { fixture, _ in try await fixture.takeFirst() },
        ActionCase(name: "rollback") { _, graph in
            let input: Map = ["sessionId": .string(firstSessionId), "index": .number(Number(firstIndex))]
            let reply = try await run(rollbackMutation, variables: ["input": input], on: graph)
            #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        },
    ]

    /// Each action gives one change that adds the new checkpoint, whose id is
    /// the id that `checkpoint` gives, with a cursor after the cursor that the
    /// subscription resumed from; the next change is the marker checkpoint.
    @Test("a take or a rollback gives one change that adds the checkpoint", arguments: actionCases)
    func eachActionGivesOneChange(_ action: ActionCase) async throws {
        let fixture = try await Fixture()
        try await fixture.takeFirst()
        try await fixture.takeFirst()
        let graph = Self.graph(of: fixture)
        let before = try await Self.cursor(of: graph)
        var subscription = try await Self.subscribe(to: graph, after: before)

        try await action.act(fixture, graph)
        let marker = try await fixture.takeFirst()
        let first = try await subscription.nextChange()
        let second = try await subscription.nextChange()

        let newId = try await Self.checkpointId(marker - 1, on: graph)
        let markerId = try await Self.checkpointId(marker, on: graph)
        #expect(first == Self.added(cursor: first.cursor, id: newId))
        #expect(second == Self.added(cursor: second.cursor, id: markerId))
        #expect(newId == "\(Self.firstSessionId):\(marker - 1)")
        #expect(try Self.sequence(of: first.cursor) > Self.sequence(of: before))
        #expect(try Self.sequence(of: second.cursor) > Self.sequence(of: first.cursor))
    }

    /// After a change, the root query `cursor` gives the cursor of that
    /// change.
    @Test("the root cursor query gives the cursor of the newest change")
    func theCursorQueryGivesTheNewestCursor() async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture)
        var subscription = try await Self.subscribe(to: graph, after: try await Self.cursor(of: graph))

        try await fixture.takeFirst()
        let change = try await subscription.nextChange()

        #expect(try await Self.cursor(of: graph) == change.cursor)
    }

    /// `changes(after:)` with the cursor of a change gives only the later
    /// changes.
    @Test("changes after a cursor gives only the later changes")
    func changesAfterACursorGivesOnlyLaterChanges() async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture)
        var live = try await Self.subscribe(to: graph, after: try await Self.cursor(of: graph))
        try await fixture.takeFirst()
        let earlier = try await live.nextChange()
        let later = try await fixture.takeFirst()
        _ = try await live.nextChange()

        var resumed = try await Self.subscribe(to: graph, after: earlier.cursor)
        let change = try await resumed.nextChange()

        #expect(change.added == [try await Self.checkpointId(later, on: graph)])
    }

    /// A checkpoint of a session key that the host does not know gives no
    /// change: the next change is the marker checkpoint.
    @Test("a checkpoint of an unknown session key gives no change")
    func anUnknownSessionKeyGivesNoChange() async throws {
        let fixture = try await Fixture(
            keys: Self.stubKeys.merging([Self.unknownSessionId: Self.unknownSessionKey]) { known, _ in known })
        let graph = Self.graph(of: fixture)
        var subscription = try await Self.subscribe(to: graph, after: try await Self.cursor(of: graph))

        try await fixture.take(owner: Self.unknownSessionId, key: Self.unknownSessionKey)
        let marker = try await fixture.takeFirst()
        let change = try await subscription.nextChange()

        #expect(change.added == [try await Self.checkpointId(marker, on: graph)])
    }

    // MARK: - Resync

    /// A cursor that the endpoint cannot resume after with no gap.
    struct ResyncCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let name: String

        /// Makes the cursor, given the fixture and its endpoint, whose change
        /// log holds one change.
        let cursor: @Sendable (Fixture, SnapshotsGraph) async throws -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// A too-old cursor, a cursor of another epoch, and a future cursor.
    static let resyncCases: [ResyncCase] = [
        ResyncCase(name: "too old") { fixture, graph in
            let old = try await cursor(of: graph)
            var subscription = try await subscribe(to: graph, after: old)
            // One change more than the log holds. Each change is read before
            // the next is made.
            for _ in 0...smallCapacity {
                try await fixture.takeFirst()
                _ = try await subscription.nextChange()
            }
            return old
        },
        ResyncCase(name: "another epoch") { _, _ in
            try await cursor(of: graph(of: try await Fixture()))
        },
        ResyncCase(name: "in the future") { _, graph in
            let current = try await cursor(of: graph)
            let epoch = try #require(current.split(separator: cursorSeparator).first)
            return "\(epoch)\(cursorSeparator)\(try sequence(of: current) + 1)"
        },
    ]

    /// A subscription after a cursor that the log cannot resume after gives
    /// one response with `RESYNC_REQUIRED`, and then ends.
    @Test("a cursor that cannot resume gives RESYNC_REQUIRED", arguments: resyncCases)
    func aCursorThatCannotResumeGivesResync(_ resync: ResyncCase) async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture, capacity: Self.smallCapacity)
        let cursor = try await resync.cursor(fixture, graph)

        var subscription = try await Self.subscribe(to: graph, after: cursor)
        let replies = try await subscription.remainingReplies()

        #expect(replies.map(\.codes) == [[Self.resyncRequired]])
    }

    // MARK: - The alias

    /// `snapshotChanges` is an alias of `changes`: the subscription runs, and
    /// the response reports the rewrite.
    @Test("snapshotChanges works through the alias")
    func snapshotChangesWorksThroughTheAlias() async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture)
        var subscription = try await Self.subscribe(
            to: graph, after: try await Self.cursor(of: graph), document: Self.aliasDocument)

        let index = try await fixture.takeFirst()
        let reply = try await subscription.nextReply()

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote("snapshotChanges", to: "changes"))
        let change = try reply.object("snapshotChanges")
        #expect(change["added"] as? [String] == [try await Self.checkpointId(index, on: graph)])
    }

    // MARK: - One change log for each store

    /// Two snapshots capabilities over one store give endpoints with the same
    /// cursor, before a change and after it (EXTRAS-9 rule 1).
    @Test("two SnapshotsCapability values over one store give the same cursor")
    func twoCapabilitiesGiveTheSameCursor() async throws {
        let fixture = try await Fixture(keys: [Self.firstSessionId: Self.firstSessionId])
        let graph = try #require(SnapshotsCapability(store: fixture.store).graphQLEndpoints.first as? SnapshotsGraph)
        let other = try #require(SnapshotsCapability(store: fixture.store).graphQLEndpoints.first as? SnapshotsGraph)
        let before = try await Self.cursor(of: graph)
        let otherBefore = try await Self.cursor(of: other)
        var subscription = try await Self.subscribe(to: graph, after: before)

        try await fixture.take(owner: Self.firstSessionId, key: Self.firstSessionId)
        let change = try await subscription.nextChange()

        #expect(otherBefore == before)
        #expect(try await Self.cursor(of: other) == change.cursor)
        #expect(try await Self.cursor(of: graph) == change.cursor)
        #expect(before != change.cursor)
    }

    // MARK: - Filters

    /// A subscription that names a session gets only the changes of that
    /// session.
    @Test("a subscription with a sessionId gets only the changes of that session")
    func aSessionIdGivesOnlyThatSession() async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture)
        var subscription = try await Self.subscribe(
            to: graph, after: try await Self.cursor(of: graph), sessionId: Self.secondSessionId)

        try await fixture.takeFirst()
        let index = try await fixture.takeSecond()
        let change = try await subscription.nextChange()

        let id = try await Self.checkpointId(index, of: Self.secondSessionId, on: graph)
        #expect(change == Self.added(cursor: change.cursor, sessionId: Self.secondSessionId, id: id))
    }

    /// An external client gets no change of a session that it does not own,
    /// while a device of the user gets it.
    @Test("an external client receives no change of a session that it does not own")
    func anExternalClientGetsOnlyItsSessions() async throws {
        let fixture = try await Fixture()
        let graph = Self.graph(of: fixture)
        let before = try await Self.cursor(of: graph)
        var external = try await Self.subscribe(
            to: graph, after: before, viewer: Self.externalViewer(owning: Self.secondSessionId))
        var device = try await Self.subscribe(to: graph, after: before)

        try await fixture.takeFirst()
        try await fixture.takeSecond()
        let externalChange = try await external.nextChange()
        let deviceChanges = [try await device.nextChange(), try await device.nextChange()]

        #expect(externalChange.sessionId == Self.secondSessionId)
        #expect(deviceChanges.map(\.sessionId) == [Self.firstSessionId, Self.secondSessionId])
        #expect(externalChange.cursor == deviceChanges.last?.cursor)
    }
}
