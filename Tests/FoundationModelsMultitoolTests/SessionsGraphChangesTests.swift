// `SessionsGraphChangesTests` — the behavioral suite of the `changes(after:)`
// subscription and the root `cursor` query of the `sessions` GraphQL endpoint
// (MT-10, task `^3xry2w9`).
//
// Each case registers its first sessions before it gets the endpoint, so the
// feed of the endpoint, which reads the events after it is made, sees only the
// changes that the case makes. A case reads the changes in order from a
// subscription, and proves that one action gave one change by the change of a
// later marker action. No case reads a clock.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `changes(after:)` subscription of the `sessions`
/// endpoint: the change of each action, the cursor, the resync, the alias,
/// the one change log of a directory, and the visibility of an external
/// client.
@Suite("SessionsGraphChangesTests", .timeLimit(.minutes(1)))
struct SessionsGraphChangesTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// The ID of a client that is not a device of the user.
    private static let externalClientId = "client-external"

    /// A device of the user, which owns no session.
    private static let deviceViewer = GraphQLViewer(clientId: deviceClientId, trust: .userDevice)

    /// The subscription of each case, with every field of a change.
    private static let changesDocument =
        "subscription($after: String) { changes(after: $after) { cursor at added changed removed } }"

    /// The subscription with the alias `sessionChanges` of `changes`.
    private static let aliasDocument =
        "subscription($after: String) { sessionChanges(after: $after) { cursor changed } }"

    /// The root query of the newest cursor.
    private static let cursorQuery = "{ cursor }"

    /// The tag that a tag case adds.
    private static let reviewTag = "review"

    /// The text of each message.
    private static let messageText = "The build is green again."

    /// The title that a marker action gives its session.
    private static let markerTitle = "Marker"

    /// The code of a subscription that cannot resume with no gap.
    private static let resyncRequired = "RESYNC_REQUIRED"

    /// The text between the epoch and the sequence number of a cursor.
    private static let cursorSeparator: Character = ":"

    // MARK: - Helpers

    /// One change of a response of the subscription.
    struct Change: Equatable {
        /// The cursor that resumes after the change.
        let cursor: String

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
                added: change["added"] as? [String] ?? [],
                changed: change["changed"] as? [String] ?? [],
                removed: change["removed"] as? [String] ?? [])
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

    /// Runs one document on `graph`.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    private static func run(
        _ document: String, viewer: GraphQLViewer? = deviceViewer, on graph: SessionsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(json: await graph.execute(query: document, variables: [:], operationName: nil, viewer: viewer))
    }

    /// The newest cursor of `graph`, from the root query `cursor`.
    ///
    /// - Parameter graph: The endpoint.
    /// - Returns: The cursor.
    /// - Throws: An error when the response has no cursor.
    private static func cursor(of graph: SessionsGraph) async throws -> String {
        try #require(try await run(cursorQuery, on: graph).data?["cursor"] as? String)
    }

    /// Starts a subscription on `graph`.
    ///
    /// - Parameters:
    ///   - graph: The endpoint.
    ///   - cursor: The cursor to resume after.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - document: The subscription document, with the variable `$after`.
    /// - Returns: The subscription.
    /// - Throws: What the endpoint throws.
    private static func subscribe(
        to graph: SessionsGraph, after cursor: String, viewer: GraphQLViewer? = deviceViewer,
        document: String = changesDocument
    ) async throws -> Subscription {
        let stream = try await graph.subscribe(
            query: document, variables: ["after": .string(cursor)], operationName: nil, viewer: viewer)
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

    /// The change of one session that a case expects.
    ///
    /// - Parameters:
    ///   - cursor: The cursor of the change, as the response gave it.
    ///   - added: The session that the change added, or `nil`.
    ///   - changed: The session that the change changed, or `nil`.
    /// - Returns: The change.
    private static func change(cursor: String, added: ULID? = nil, changed: ULID? = nil) -> Change {
        Change(
            cursor: cursor, added: [added].compactMap { $0?.ulidString },
            changed: [changed].compactMap { $0?.ulidString }, removed: [])
    }

    /// A marker action: gives `marker` a new title, which changes it once.
    ///
    /// - Parameters:
    ///   - marker: The marker session.
    ///   - directory: The directory.
    /// - Throws: What the directory throws.
    private static func mark(_ marker: SessionSummary, in directory: InMemorySessionDirectory) async throws {
        _ = try await directory.setTitle(markerTitle, of: marker.id)
    }

    /// A client that is not a device of the user, and that owns `owned`.
    ///
    /// - Parameter owned: The session that the client owns.
    /// - Returns: The viewer.
    private static func externalViewer(owning owned: SessionSummary) -> GraphQLViewer {
        GraphQLViewer(clientId: externalClientId, trust: .external, ownedSessions: [owned.id.ulidString])
    }

    // MARK: - The change of each action

    /// One action on a target session, its mutation, and the target that its
    /// one change names as changed.
    struct ActionCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let name: String

        /// Makes the target ready before the endpoint exists, for example
        /// starts a turn so that a message waits in its queue.
        let prepare: @Sendable (ULID, InMemorySessionDirectory) throws -> Void

        /// The mutation document on the target.
        let mutation: @Sendable (ULID) -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// Tag, send and archive, each of which gives one change of its target.
    static let actionCases: [ActionCase] = [
        ActionCase(
            name: "tag",
            prepare: { _, _ in },
            mutation: { target in
                "mutation { tagSession(input: {id: \"\(target.ulidString)\", tags: [\"\(reviewTag)\"]}) { id } }"
            }),
        ActionCase(
            name: "send to a working session",
            prepare: { target, directory in try directory.startUserTurn(of: target) },
            mutation: { target in
                "mutation { sendMessage(input: {to: \"\(target.ulidString)\", message: \"\(messageText)\"}) "
                    + "{ outcome } }"
            }),
        ActionCase(
            name: "archive",
            prepare: { _, _ in },
            mutation: { target in "mutation { archiveSession(input: {id: \"\(target.ulidString)\"}) { id } }" }),
    ]

    /// Each action gives one change that names its target, with a cursor
    /// after the cursor that the subscription resumed from; the next change
    /// is the change of the marker.
    @Test("tag, send and archive each give one change with a newer cursor", arguments: actionCases)
    func eachActionGivesOneChange(_ action: ActionCase) async throws {
        let directory = Fixtures.directoryWithLauncher()
        let target = Fixtures.summary()
        let marker = Fixtures.summary()
        directory.register(target)
        directory.register(marker)
        try action.prepare(target.id, directory)
        let graph = SessionsGraph.endpoint(of: directory)
        let before = try await Self.cursor(of: graph)
        var subscription = try await Self.subscribe(to: graph, after: before)

        let reply = try await Self.run(action.mutation(target.id), on: graph)
        try await Self.mark(marker, in: directory)
        let first = try await subscription.nextChange()
        let second = try await subscription.nextChange()

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(first == Self.change(cursor: first.cursor, changed: target.id))
        #expect(second == Self.change(cursor: second.cursor, changed: marker.id))
        #expect(try Self.sequence(of: first.cursor) > Self.sequence(of: before))
        #expect(try Self.sequence(of: second.cursor) > Self.sequence(of: first.cursor))
    }

    /// A start gives the new root session as added (section 11.5), then the
    /// change of its first turn, each with a newer cursor.
    @Test("a start gives the new session as added, then the change of its first turn")
    func aStartGivesAddedThenTheTurn() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let graph = SessionsGraph.endpoint(of: directory)
        let before = try await Self.cursor(of: graph)
        var subscription = try await Self.subscribe(to: graph, after: before)

        let reply = try await Self.run(
            "mutation { startSession(input: {agentId: \"\(Fixtures.agentID)\", message: \"\(Self.messageText)\"}) "
                + "{ id } }",
            on: graph)
        let startedID = try #require(try reply.object("startSession")["id"] as? String)
        let started = try #require(ULID(ulidString: startedID))
        let added = try await subscription.nextChange()
        let turn = try await subscription.nextChange()

        #expect(added == Self.change(cursor: added.cursor, added: started))
        #expect(turn == Self.change(cursor: turn.cursor, changed: started))
        #expect(try Self.sequence(of: added.cursor) > Self.sequence(of: before))
        #expect(try Self.sequence(of: turn.cursor) > Self.sequence(of: added.cursor))
    }

    /// After a change, the root query `cursor` gives the cursor of that
    /// change.
    @Test("the root cursor query gives the cursor of the newest change")
    func theCursorQueryGivesTheNewestCursor() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let marker = Fixtures.summary()
        directory.register(marker)
        let graph = SessionsGraph.endpoint(of: directory)
        var subscription = try await Self.subscribe(to: graph, after: try await Self.cursor(of: graph))

        try await Self.mark(marker, in: directory)
        let change = try await subscription.nextChange()

        #expect(try await Self.cursor(of: graph) == change.cursor)
    }

    // MARK: - Resync

    /// A cursor that the endpoint cannot resume after with no gap.
    struct ResyncCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test report.
        let name: String

        /// Makes the cursor, given the endpoint, its directory and one
        /// session of the directory.
        let cursor: @Sendable (SessionsGraph, InMemorySessionDirectory, SessionSummary) async throws -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// A too-old cursor, a cursor of another epoch, and a future cursor.
    static let resyncCases: [ResyncCase] = [
        ResyncCase(name: "too old") { graph, directory, session in
            let old = try await cursor(of: graph)
            var subscription = try await subscribe(to: graph, after: old)
            // One change more than the log holds. Each change is read before
            // the next is made, so the feed of the directory loses none.
            for index in 0...SessionsGraph.changeLogCapacity {
                _ = try await directory.setTitle("\(markerTitle) \(index)", of: session.id)
                _ = try await subscription.nextChange()
            }
            return old
        },
        ResyncCase(name: "another epoch") { _, _, _ in
            try await cursor(of: SessionsGraph.endpoint(of: InMemorySessionDirectory()))
        },
        ResyncCase(name: "in the future") { graph, _, _ in
            let current = try await cursor(of: graph)
            let epoch = try #require(current.split(separator: cursorSeparator).first)
            return "\(epoch)\(cursorSeparator)\(try sequence(of: current) + 1)"
        },
    ]

    /// A subscription after a cursor that the log cannot resume after gives
    /// one response with `RESYNC_REQUIRED`, and then ends.
    @Test("a cursor that cannot resume gives RESYNC_REQUIRED", arguments: resyncCases)
    func aCursorThatCannotResumeGivesResync(_ resync: ResyncCase) async throws {
        let directory = Fixtures.directoryWithLauncher()
        let session = Fixtures.summary()
        directory.register(session)
        let graph = SessionsGraph.endpoint(of: directory)
        let cursor = try await resync.cursor(graph, directory, session)

        var subscription = try await Self.subscribe(to: graph, after: cursor)
        let replies = try await subscription.remainingReplies()

        #expect(replies.map(\.codes) == [[Self.resyncRequired]])
    }

    // MARK: - The alias

    /// `sessionChanges` is an alias of `changes`: the subscription runs, and
    /// the response reports the rewrite.
    @Test("sessionChanges works through the alias")
    func sessionChangesWorksThroughTheAlias() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let marker = Fixtures.summary()
        directory.register(marker)
        let graph = SessionsGraph.endpoint(of: directory)
        var subscription = try await Self.subscribe(
            to: graph, after: try await Self.cursor(of: graph), document: Self.aliasDocument)

        try await Self.mark(marker, in: directory)
        let reply = try await subscription.nextReply()

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote("sessionChanges", to: "changes"))
        #expect(try reply.object("sessionChanges")["changed"] as? [String] == [marker.id.ulidString])
    }

    // MARK: - One change log for each directory

    /// Two copies of the tool give endpoints with the same cursor, before a
    /// change and after it (EXTRAS-9 rule 1).
    @Test("two copies of the tool give endpoints with the same cursor")
    func copiesOfTheToolGiveTheSameCursor() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let marker = Fixtures.summary()
        directory.register(marker)
        let tool = try SessionsTool(directory: directory)
        let copy = tool
        let graph = try #require(tool.graphQLEndpoints.first as? SessionsGraph)
        let copiedGraph = try #require(copy.graphQLEndpoints.first as? SessionsGraph)
        let before = try await Self.cursor(of: graph)
        var subscription = try await Self.subscribe(to: graph, after: before)

        try await Self.mark(marker, in: directory)
        let change = try await subscription.nextChange()

        #expect(try await Self.cursor(of: copiedGraph) == change.cursor)
        #expect(try await Self.cursor(of: graph) == change.cursor)
        #expect(before != change.cursor)
    }

    // MARK: - Visibility

    /// An external client gets no change of a session that it cannot see:
    /// the change of a stranger is not sent to it, while a device of the user
    /// gets it.
    @Test("an external client receives no change of a session that it cannot see")
    func anExternalClientGetsNoChangeOfAHiddenSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let owned = Fixtures.summary()
        let subagent = Fixtures.summary(kind: .subagent, parentID: owned.id)
        let stranger = Fixtures.summary()
        for session in [owned, subagent, stranger] {
            directory.register(session)
        }
        let graph = SessionsGraph.endpoint(of: directory)
        let before = try await Self.cursor(of: graph)
        var external = try await Self.subscribe(to: graph, after: before, viewer: Self.externalViewer(owning: owned))
        var device = try await Self.subscribe(to: graph, after: before)

        try await Self.mark(stranger, in: directory)
        try await Self.mark(subagent, in: directory)
        let externalChange = try await external.nextChange()
        let deviceChanges = [try await device.nextChange(), try await device.nextChange()]

        #expect(externalChange.changed == [subagent.id.ulidString])
        #expect(deviceChanges.map(\.changed) == [[stranger.id.ulidString], [subagent.id.ulidString]])
        #expect(externalChange.cursor == deviceChanges.last?.cursor)
    }

    /// A root session that a session of the client starts reaches the client
    /// as added: the client sees the sessions that its sessions started.
    @Test("a root session that an owned session starts reaches its owner as added")
    func aStartedSessionReachesItsOwnerAsAdded() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let owned = Fixtures.summary()
        directory.register(owned)
        let graph = SessionsGraph.endpoint(of: directory)
        var external = try await Self.subscribe(
            to: graph, after: try await Self.cursor(of: graph), viewer: Self.externalViewer(owning: owned))

        let started = Fixtures.summary(startedBy: owned.id)
        directory.register(started)
        let change = try await external.nextChange()

        #expect(change == Self.change(cursor: change.cursor, added: started.id))
    }
}
