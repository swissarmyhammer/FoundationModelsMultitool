// `SessionsGraphShareTests` — the `share` field of a session and the share
// mutations of the `sessions` GraphQL endpoint (D208 (k), task `^ysybpdp`),
// and the share changes in the change feed of the endpoint.
//
// Each case registers its sessions in its own `InMemorySessionDirectory`,
// gives the endpoint of that directory a fake sharer, and reads the calls of
// the fake after the call. A case that reads the change feed registers its
// sessions before it subscribes, reads the changes in order from the
// subscription, and proves that one action gave one change by the change of
// a later marker action. No case reads a clock or waits for a time.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `share` field of a session, the mutations
/// `shareSession`, `updateSessionShare` and `stopSharingSession`, and the
/// change entry of each share change.
@Suite("SessionsGraphShareTests", .ownsTemporaryDirectories, .timeLimit(.minutes(1)))
struct SessionsGraphShareTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The suite of the change feed, whose subscription helper each change
    /// case uses.
    private typealias Changes = SessionsGraphChangesTests

    /// A device of the user, which owns no session.
    private static let deviceViewer = Changes.deviceViewer

    /// The code of the toolkit for a session that the viewer cannot see or
    /// does not own.
    private static let notFound = "NOT_FOUND"

    /// The title that a marker action gives its session.
    private static let markerTitle = "Marker"

    /// The `session` query of one id, with each field of its share.
    private static let shareQuery = """
        query($id: ID!) { session(id: $id) { share { url anyoneWithLink updatedAt \
        options { includeThoughts includeToolOutput anyoneWithLink keepUpdated } } } }
        """

    /// The options of a share that has all four options different from the
    /// defaults of a share.
    private static let otherOptions = SessionShareOptions(
        includeThoughts: false, includeToolOutput: false, anyoneWithLink: false, keepUpdated: true)

    /// The `shareSession` mutation of one id, with no options.
    private static let shareMutation = "mutation($id: ID!) { shareSession(input: {id: $id}) { id share { url } } }"

    /// The `shareSession` mutation of one id, with ``otherOptions``.
    private static let shareWithOptionsMutation = """
        mutation($id: ID!) { shareSession(input: {id: $id, options: {includeThoughts: false, \
        includeToolOutput: false, anyoneWithLink: false, keepUpdated: true}}) { id } }
        """

    /// The `updateSessionShare` mutation of one id, which turns on the
    /// switch Keep Updated.
    private static let updateMutation =
        "mutation($id: ID!) { updateSessionShare(input: {id: $id, keepUpdated: true}) { id } }"

    /// The `stopSharingSession` mutation of one id.
    private static let stopMutation =
        "mutation($id: ID!) { stopSharingSession(input: {id: $id}) { id share { url } } }"

    // MARK: - Helpers

    /// One session in its own directory, a fake sharer, and the endpoint of
    /// that directory with that sharer.
    private struct Setup {
        /// The directory that holds ``session`` and ``marker``.
        let directory = Fixtures.directoryWithLauncher()

        /// The session of the case.
        let session: SessionSummary

        /// A second session, whose change marks the end of the changes of a
        /// case.
        let marker = Fixtures.summary()

        /// The fake sharer of the endpoint.
        let sharer: RecordingSessionSharer

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Registers the sessions, gives the session a share with `options`,
        /// and gives the sharer to the endpoint.
        ///
        /// - Parameter options: The options of the share of the session, or
        ///   `nil` for a session with no share. The default is no share.
        init(sharedWith options: SessionShareOptions? = nil) {
            let session = Fixtures.summary()
            self.session = session
            directory.register(session)
            directory.register(marker)
            let shares = options.map { [session.id: RecordingSessionSharer.share(of: session.id, options: $0)] }
            sharer = RecordingSessionSharer(shares: shares ?? [:])
            graph = SessionsGraph.endpoint(of: directory, sharer: sharer)
        }

        /// The id of ``session`` as a variable.
        var variables: [String: Map] {
            ["id": .string(session.id.ulidString)]
        }

        /// Runs one document on ``graph``, with the id of ``session``.
        ///
        /// - Parameters:
        ///   - document: The document.
        ///   - viewer: The client of the call. The default is a device of the
        ///     user.
        /// - Returns: The response.
        /// - Throws: What the endpoint throws.
        func run(_ document: String, viewer: GraphQLViewer? = deviceViewer) async throws -> GraphQLReply {
            try await GraphQLReply.run(document, variables: variables, viewer: viewer, on: graph)
        }

        /// Starts a subscription of the changes after the newest change.
        ///
        /// - Parameter viewer: The client of the subscription. The default is
        ///   a device of the user.
        /// - Returns: The subscription.
        /// - Throws: What the endpoint throws.
        func subscribe(viewer: GraphQLViewer = deviceViewer) async throws -> Changes.Subscription {
            let cursor = try await GraphQLReply.cursor(of: graph, viewer: viewer)
            return try await Changes.subscribe(to: graph, after: cursor, viewer: viewer)
        }

        /// A marker action: gives ``marker`` a new title, which changes it
        /// once.
        ///
        /// - Throws: What the directory throws.
        func mark() async throws {
            _ = try await directory.setTitle(markerTitle, of: marker.id)
        }
    }

    // MARK: - The share field

    @Test("the share field of a session with a share gives the link, the state, the options and the time")
    func theShareFieldGivesTheShare() async throws {
        let setup = Setup(sharedWith: Self.otherOptions)

        let reply = try await setup.run(Self.shareQuery)

        let share = try #require(try reply.object("session")["share"] as? [String: Any], "errors: \(reply.messages)")
        #expect(share["url"] as? String == RecordingSessionSharer.url(of: setup.session.id).absoluteString)
        #expect(share["anyoneWithLink"] as? Bool == false)
        #expect(share["updatedAt"] as? String == DateTime(RecordingSessionSharer.updatedAt).rfc3339)
        #expect(
            share["options"] as? [String: Bool]
                == ["includeThoughts": false, "includeToolOutput": false, "anyoneWithLink": false, "keepUpdated": true])
    }

    @Test("the share field of a session with no share is null")
    func theShareFieldOfASessionWithNoShareIsNull() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.shareQuery)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(try reply.object("session")["share"] is NSNull)
    }

    @Test("the share field on a server with no sharer gives SHARING_UNAVAILABLE")
    func theShareFieldWithNoSharerGivesSharingUnavailable() async throws {
        let directory = InMemorySessionDirectory()
        let session = Fixtures.summary()
        directory.register(session)

        let reply = try await GraphQLReply.run(
            Self.shareQuery, variables: ["id": .string(session.id.ulidString)], viewer: Self.deviceViewer,
            on: SessionsGraph.endpoint(of: directory))

        #expect(reply.codes == ["SHARING_UNAVAILABLE"])
    }

    // MARK: - The mutations

    @Test("shareSession with no options shares the session with the defaults, and gives its share")
    func shareSessionSharesWithTheDefaults() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.shareMutation)

        #expect(await setup.sharer.calls == [.share(setup.session.id, .defaults)])
        let share = try #require(try reply.object("shareSession")["share"] as? [String: Any])
        #expect(share["url"] as? String == RecordingSessionSharer.url(of: setup.session.id).absoluteString)
    }

    @Test("shareSession with options gives the options to the sharer")
    func shareSessionGivesTheOptions() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.shareWithOptionsMutation)

        #expect(await setup.sharer.calls == [.share(setup.session.id, Self.otherOptions)])
    }

    @Test("shareSession of a session with a share keeps that share and calls no share of the sharer")
    func shareSessionOfASharedSessionKeepsTheShare() async throws {
        let setup = Setup(sharedWith: .defaults)

        let reply = try await setup.run(Self.shareMutation)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(await setup.sharer.calls.isEmpty)
    }

    @Test("updateSessionShare updates the share with the options of the share and the new Keep Updated switch")
    func updateSessionShareUpdatesTheShare() async throws {
        let setup = Setup(sharedWith: .defaults)

        _ = try await setup.run(Self.updateMutation)

        var expected = SessionShareOptions.defaults
        expected.keepUpdated = true
        #expect(await setup.sharer.calls == [.update(setup.session.id, expected)])
    }

    @Test("stopSharingSession stops the share, and gives the session with no share")
    func stopSharingSessionStopsTheShare() async throws {
        let setup = Setup(sharedWith: .defaults)

        let reply = try await setup.run(Self.stopMutation)

        #expect(await setup.sharer.calls == [.stop(setup.session.id)])
        #expect(try reply.object("stopSharingSession")["share"] is NSNull)
    }

    /// One share mutation and the tool op that shares its work.
    struct MutationCase: Sendable, CustomTestStringConvertible {
        /// The mutation document, with the variable `$id`.
        let mutation: String

        /// The op string of the tool op.
        let op: String

        /// The name of the case in the test report.
        var testDescription: String { op }
    }

    /// The `updateSessionShare` and the `stopSharingSession` mutation.
    static let notSharedCases = [
        MutationCase(mutation: updateMutation, op: "update share"),
        MutationCase(mutation: stopMutation, op: "stop sharing"),
    ]

    @Test(
        "an update or a stop of a session with no share gives NOT_SHARED with the corrective of the tool",
        arguments: notSharedCases)
    func anUnsharedSessionGivesNotShared(_ call: MutationCase) async throws {
        let setup = Setup()
        let tool = try SessionsTool(directory: setup.directory)

        let answer = try await Fixtures.asCaller(in: setup.directory) { _ in
            try await tool.call(arguments: Fixtures.payload(call.op, [("id", setup.session.id.ulidString)]))
        }
        let reply = try await setup.run(call.mutation)

        #expect(reply.codes == ["NOT_SHARED"])
        #expect(reply.messages == [answer])
    }

    // MARK: - The external client

    @Test("an external client cannot share a session that it sees but does not own")
    func anExternalClientCannotShareASessionItDoesNotOwn() async throws {
        let setup = Setup()
        let viewer = GraphQLViewer.external(started: [setup.session.id.ulidString])

        let reply = try await setup.run(Self.shareMutation, viewer: viewer)

        #expect(reply.codes == [Self.notFound])
        #expect(await setup.sharer.calls.isEmpty)
    }

    @Test("an external client shares a session that it owns")
    func anExternalClientSharesASessionItOwns() async throws {
        let setup = Setup()
        let viewer = GraphQLViewer.external(owning: [setup.session.id.ulidString])

        _ = try await setup.run(Self.shareMutation, viewer: viewer)

        #expect(await setup.sharer.calls == [.share(setup.session.id, .defaults)])
    }

    // MARK: - The aliases

    /// A mutation that writes an alias, the alias, and the name of the
    /// schema that the alias reaches (D86).
    struct AliasCase: Sendable, CustomTestStringConvertible {
        /// The document, with the variable `$id`.
        let document: String

        /// The alias that the document writes.
        let from: String

        /// The name of the schema that the alias reaches.
        let to: String

        /// The name of the case in the test report.
        var testDescription: String { "\(from) to \(to)" }
    }

    /// The aliases of the mutation names and of the input fields.
    static let aliasCases = [
        AliasCase(
            document: "mutation($id: ID!) { updateShare(input: {id: $id}) { id } }", from: "updateShare",
            to: "updateSessionShare"),
        AliasCase(
            document: "mutation($id: ID!) { stopSharing(input: {id: $id}) { id } }", from: "stopSharing",
            to: "stopSharingSession"),
        AliasCase(
            document: "mutation($id: ID!) { shareSession(input: {sessionId: $id}) { id } }", from: "sessionId",
            to: "id"),
        AliasCase(
            document: "mutation($id: ID!) { shareSession(input: {id: $id, options: {thoughts: false}}) { id } }",
            from: "thoughts", to: "includeThoughts"),
    ]

    @Test(
        "each alias of a share mutation reaches its name, and the response reports the rewrite",
        arguments: aliasCases)
    func eachAliasReachesItsName(_ alias: AliasCase) async throws {
        let setup = Setup(sharedWith: .defaults)

        let reply = try await setup.run(alias.document)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote(alias.from, to: alias.to), "rewrites: \(reply.rewrites)")
    }

    // MARK: - The change feed

    /// One mutation that changes a share, and the options of the share that
    /// the session has before the mutation.
    struct ChangeCase: Sendable, CustomTestStringConvertible {
        /// The mutation document, with the variable `$id`.
        let mutation: String

        /// The options of the share before the mutation, or `nil` for no
        /// share.
        let before: SessionShareOptions?

        /// The name of the case in the test report.
        let name: String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// A share of a session with no share, an update and a stop.
    static let changeCases = [
        ChangeCase(mutation: shareMutation, before: nil, name: "shareSession"),
        ChangeCase(mutation: updateMutation, before: .defaults, name: "updateSessionShare"),
        ChangeCase(mutation: stopMutation, before: .defaults, name: "stopSharingSession"),
    ]

    @Test("a share mutation gives one changed entry for its session", arguments: changeCases)
    func aShareMutationGivesOneChangedEntry(_ change: ChangeCase) async throws {
        let setup = Setup(sharedWith: change.before)
        var subscription = try await setup.subscribe()

        let reply = try await setup.run(change.mutation)
        try await setup.mark()
        let changes = [try await subscription.nextChange(), try await subscription.nextChange()]

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(changes.map(\.changed) == [[setup.session.id.ulidString], [setup.marker.id.ulidString]])
    }

    @Test("shareSession of a session with a share gives no change entry")
    func shareSessionOfASharedSessionGivesNoChange() async throws {
        let setup = Setup(sharedWith: .defaults)
        var subscription = try await setup.subscribe()

        _ = try await setup.run(Self.shareMutation)
        try await setup.mark()
        let change = try await subscription.nextChange()

        #expect(change.changed == [setup.marker.id.ulidString])
    }

    @Test("share session of the tool gives one changed entry for its session")
    func theShareOperationOfTheToolGivesOneChangedEntry() async throws {
        let setup = Setup()
        let tool = try SessionsTool(directory: setup.directory)
        var subscription = try await setup.subscribe()

        let callerID = try await Fixtures.asCaller(in: setup.directory) { callerID in
            _ = try await tool.call(
                arguments: Fixtures.payload("share session", [("id", setup.session.id.ulidString)]))
            return callerID
        }
        try await setup.mark()
        let changes = [
            try await subscription.nextChange(), try await subscription.nextChange(),
            try await subscription.nextChange(),
        ]

        // The add of the caller and the change of the share come from two feeds, so their order
        // is not fixed. The marker change comes after both.
        let firstTwo = changes.prefix(2).map { ChangeEntries(added: $0.added, changed: $0.changed) }
        #expect(
            Set(firstTwo)
                == [
                    ChangeEntries(added: [callerID.ulidString], changed: []),
                    ChangeEntries(added: [], changed: [setup.session.id.ulidString]),
                ])
        #expect(changes[2].added.isEmpty)
        #expect(changes[2].changed == [setup.marker.id.ulidString])
    }

    /// The added and the changed entries of one change, with no cursor.
    private struct ChangeEntries: Hashable {
        /// The added entries.
        let added: [String]

        /// The changed entries.
        let changed: [String]
    }

    @Test("a share change from outside gives one changed entry for its session")
    func aShareChangeFromOutsideGivesOneChangedEntry() async throws {
        let setup = Setup()
        var subscription = try await setup.subscribe()

        setup.sharer.yieldChange(of: setup.session.id)
        let change = try await subscription.nextChange()

        #expect(change == Changes.Change(cursor: change.cursor, added: [], changed: [setup.session.id.ulidString], removed: []))
    }

    @Test("an external client receives a share change from outside only for a session that it can see")
    func anExternalClientGetsAShareChangeOnlyWhenVisible() async throws {
        let setup = Setup()
        var subscription = try await setup.subscribe(viewer: .external(owning: [setup.session.id.ulidString]))

        setup.sharer.yieldChange(of: setup.marker.id)
        setup.sharer.yieldChange(of: setup.session.id)
        let change = try await subscription.nextChange()

        #expect(change.changed == [setup.session.id.ulidString])
    }

    // MARK: - The subscription of the share changes

    @Test("a later endpoint call with the sharer starts no second read of the share changes")
    func aLaterEndpointCallStartsNoSecondRead() async throws {
        let setup = Setup()

        let again = SessionsGraph.endpoint(of: setup.directory, sharer: setup.sharer)

        #expect(again === setup.graph)
        #expect(setup.sharer.shareChangesCalls == 1)
    }

    @Test("the read of the share changes ends when the endpoint is released")
    func theReadOfTheShareChangesEndsWithTheEndpoint() async {
        let directory = InMemorySessionDirectory()
        let sharer = RecordingSessionSharer()
        var graph: SessionsGraph? = SessionsGraph.endpoint(of: directory, sharer: sharer)
        #expect(graph != nil)

        graph = nil
        await sharer.waitForTheEndOfTheShareChanges()

        #expect(sharer.shareChangesCalls == 1)
    }
}
