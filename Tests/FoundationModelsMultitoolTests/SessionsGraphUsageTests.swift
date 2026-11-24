// `SessionsGraphUsageTests` — the behavioral suite of the Pinned and Recent
// lists of the `sessions` GraphQL endpoint (MT-10, D118): the
// `pinnedSessions` and `recentSessions` queries, and the pin facts of a
// session.
//
// Each case registers its sessions with fixed pin and last-use times in its
// own `InMemorySessionDirectory`. No case reads a clock or waits.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the Pinned and Recent lists of the `sessions`
/// GraphQL endpoint.
@Suite("SessionsGraphUsageTests")
struct SessionsGraphUsageTests {

    // MARK: - Constants

    /// The shared fixtures of the sessions tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The `pinnedSessions` query, with the row of the Pinned list.
    private static let pinnedQuery = "{ pinnedSessions { id title cwd } }"

    /// The `recentSessions` query, with the row of the Recent list.
    private static let recentQuery = "{ recentSessions { id title cwd } }"

    /// The `recentSessions` query, with a limit.
    private static let limitedRecentQuery = "query($limit: Int) { recentSessions(limit: $limit) { id } }"

    /// The `pinnedSessions` query, with the short id and the slug of each
    /// row.
    private static let pinnedNamesQuery = "{ pinnedSessions { shortId slug } }"

    /// The `recentSessions` query, with the short id and the slug of each
    /// row.
    private static let recentNamesQuery = "{ recentSessions { shortId slug } }"

    /// The slug of the title of ``Usage/firstPin``.
    private static let firstPinSlug = "first-pin"

    /// The slug of the title of ``Usage/newest``.
    private static let newestSlug = "newest"

    /// The `session` query of the pin facts of one session.
    private static let pinFactsQuery = "query($id: ID!) { session(id: $id) { pinned pinnedAt lastUsedAt } }"

    /// A limit that the `recentSessions` case names.
    private static let smallLimit = 2

    /// The time `offset` seconds after the fixed time of the fixtures.
    ///
    /// - Parameter offset: The seconds after the fixed time.
    /// - Returns: The time.
    private static func time(_ offset: TimeInterval) -> Date {
        Fixtures.fixedDate.addingTimeInterval(offset)
    }

    // MARK: - Helpers

    /// The sessions of one case: two pinned, three used and one that no
    /// client opened, registered so that no order of registration gives the
    /// expected order.
    private struct Usage {
        /// The directory. Its clock is after each time of the registered
        /// sessions, thus a new pin goes after the registered pins.
        let directory = InMemorySessionDirectory(now: { SessionsGraphUsageTests.time(1_000) })

        /// The endpoint over the directory.
        let graph: SessionsGraph

        /// The first pin, which a client also used last of all.
        let firstPin = Fixtures.summary(
            title: "First pin", folder: URL(fileURLWithPath: "/work/one"), pinnedAt: time(10), lastUsedAt: time(500))

        /// The second pin.
        let secondPin = Fixtures.summary(title: "Second pin", pinnedAt: time(20))

        /// The session that a client used last, of the sessions that are not
        /// pinned.
        let newest = Fixtures.summary(title: "Newest", folder: URL(fileURLWithPath: "/work/two"), lastUsedAt: time(300))

        /// A session that a client used between the two others.
        let middle = Fixtures.summary(title: "Middle", lastUsedAt: time(200))

        /// The session that a client used first.
        let oldest = Fixtures.summary(title: "Oldest", lastUsedAt: time(100))

        /// A session that no client opened.
        let unused = Fixtures.summary(title: "Unused")

        /// Registers each session, in an order that is not the order of a
        /// list.
        init() {
            for summary in [middle, secondPin, unused, oldest, firstPin, newest] {
                directory.register(summary)
            }
            graph = SessionsGraph.endpoint(of: directory)
        }
    }

    /// The id of each row of one list of a response.
    ///
    /// - Parameters:
    ///   - key: The name of the list.
    ///   - reply: The response.
    /// - Returns: The ids, in order.
    /// - Throws: An error when the response has no such list.
    private static func ids(_ key: String, of reply: GraphQLReply) throws -> [String] {
        try reply.list(key).compactMap { $0["id"] as? String }
    }

    /// The id of each summary, as the endpoint writes it.
    ///
    /// - Parameter summaries: The summaries.
    /// - Returns: The ids, in order.
    private static func ids(_ summaries: [SessionSummary]) -> [String] {
        summaries.map(\.id.ulidString)
    }

    // MARK: - pinnedSessions

    /// The Pinned list gives each pinned session in pin order, the first
    /// pin first, with the row that the sidebar reads.
    @Test("pinnedSessions gives the pinned sessions in pin order, with id, title and cwd")
    func pinnedSessionsAreInPinOrder() async throws {
        let usage = Usage()

        let rows = try await GraphQLReply.run(Self.pinnedQuery, on: usage.graph).list("pinnedSessions")

        #expect(rows.compactMap { $0["id"] as? String } == Self.ids([usage.firstPin, usage.secondPin]))
        #expect(rows.first?["title"] as? String == usage.firstPin.title)
        #expect(rows.first?["cwd"] as? String == usage.firstPin.workingDirectory.path)
    }

    /// Each row of the Pinned list has the short id and the slug of its
    /// session.
    @Test("pinnedSessions gives the shortId and the slug of each row")
    func pinnedSessionsGivesTheShortIDAndTheSlug() async throws {
        let usage = Usage()

        let row = try #require(
            try await GraphQLReply.run(Self.pinnedNamesQuery, on: usage.graph).list("pinnedSessions").first)

        #expect(row["shortId"] as? String == usage.firstPin.shortID)
        #expect(row["slug"] as? String == Self.firstPinSlug)
    }

    /// A directory with no pin gives an empty Pinned list.
    @Test("pinnedSessions is empty when no session is pinned")
    func pinnedSessionsIsEmptyWithNoPin() async throws {
        let directory = InMemorySessionDirectory()
        directory.register(Fixtures.summary(lastUsedAt: Self.time(100)))

        let ids = try Self.ids(
            "pinnedSessions", of: await GraphQLReply.run(Self.pinnedQuery, on: SessionsGraph.endpoint(of: directory)))

        #expect(ids.isEmpty)
    }

    // MARK: - recentSessions

    /// The Recent list gives the used sessions, the last one first, with no
    /// pinned session and no session that a client never opened.
    @Test("recentSessions gives the used sessions newest first, with no pinned and no unused session")
    func recentSessionsAreNewestFirstWithNoPin() async throws {
        let usage = Usage()

        let rows = try await GraphQLReply.run(Self.recentQuery, on: usage.graph).list("recentSessions")

        #expect(rows.compactMap { $0["id"] as? String } == Self.ids([usage.newest, usage.middle, usage.oldest]))
        #expect(rows.first?["title"] as? String == usage.newest.title)
        #expect(rows.first?["cwd"] as? String == usage.newest.workingDirectory.path)
    }

    /// Each row of the Recent list has the short id and the slug of its
    /// session.
    @Test("recentSessions gives the shortId and the slug of each row")
    func recentSessionsGivesTheShortIDAndTheSlug() async throws {
        let usage = Usage()

        let row = try #require(
            try await GraphQLReply.run(Self.recentNamesQuery, on: usage.graph).list("recentSessions").first)

        #expect(row["shortId"] as? String == usage.newest.shortID)
        #expect(row["slug"] as? String == Self.newestSlug)
    }

    /// The limit cuts the Recent list after the newest sessions.
    @Test("recentSessions gives at most the limit, the newest first")
    func recentSessionsHonorsTheLimit() async throws {
        let usage = Usage()

        let reply = try await GraphQLReply.run(
            Self.limitedRecentQuery, variables: ["limit": .int(Self.smallLimit)], on: usage.graph)

        #expect(try Self.ids("recentSessions", of: reply) == Self.ids([usage.newest, usage.middle]))
    }

    // MARK: - Visibility

    /// An external client sees in each list only the sessions that it can
    /// see.
    @Test("an external viewer sees only its own sessions in the Pinned and Recent lists")
    func anExternalViewerSeesOnlyItsSessions() async throws {
        let usage = Usage()
        let viewer = GraphQLViewer.external(owning: [usage.secondPin.id.ulidString, usage.middle.id.ulidString])

        let pinnedReply = try await GraphQLReply.run(Self.pinnedQuery, viewer: viewer, on: usage.graph)
        let recentReply = try await GraphQLReply.run(Self.recentQuery, viewer: viewer, on: usage.graph)
        let pinned = try Self.ids("pinnedSessions", of: pinnedReply)
        let recent = try Self.ids("recentSessions", of: recentReply)

        #expect(pinned == Self.ids([usage.secondPin]))
        #expect(recent == Self.ids([usage.middle]))
    }

    // MARK: - The pin facts of a session

    /// A pinned session reads `pinned`, its pin time and its last-use time.
    @Test("a pinned session reads pinned, pinnedAt and lastUsedAt")
    func aPinnedSessionReadsItsPinFacts() async throws {
        let usage = Usage()

        let facts = try await GraphQLReply.run(
            Self.pinFactsQuery, variables: ["id": .string(usage.firstPin.id.ulidString)], on: usage.graph
        ).object("session")

        #expect(facts["pinned"] as? Bool == true)
        #expect(facts["pinnedAt"] as? String != nil)
        #expect(facts["lastUsedAt"] as? String != nil)
    }

    /// A session that is not pinned and that no client opened reads `false`
    /// and two nulls.
    @Test("an unused session reads pinned false and null times")
    func anUnusedSessionReadsNoPinFacts() async throws {
        let usage = Usage()

        let reply = try await GraphQLReply.run(
            Self.pinFactsQuery, variables: ["id": .string(usage.unused.id.ulidString)], on: usage.graph)
        let facts = try reply.object("session")

        #expect(facts["pinned"] as? Bool == false)
        #expect(facts["pinnedAt"] is NSNull)
        #expect(facts["lastUsedAt"] is NSNull)
    }

    // MARK: - pinSession and unpinSession

    /// The mutation document of `name` on the session `id`.
    ///
    /// - Parameters:
    ///   - name: `pinSession` or `unpinSession`.
    ///   - id: The session id.
    /// - Returns: The document.
    private static func mutation(_ name: String, _ id: ULID) -> String {
        "mutation { \(name)(input: {id: \"\(id.ulidString)\"}) { id pinned } }"
    }

    /// A pin puts the session at the end of the Pinned list and out of the
    /// Recent list; a second pin keeps its place; an unpin puts it back in
    /// the Recent list.
    @Test("pinSession, a second pin and unpinSession change the two lists")
    func pinAndUnpinChangeTheLists() async throws {
        let usage = Usage()

        let pin = try await GraphQLReply.run(Self.mutation("pinSession", usage.newest.id), on: usage.graph)
        let pinnedAfterPin = try Self.ids(
            "pinnedSessions", of: await GraphQLReply.run(Self.pinnedQuery, on: usage.graph))
        let recentAfterPin = try Self.ids(
            "recentSessions", of: await GraphQLReply.run(Self.recentQuery, on: usage.graph))
        _ = try await GraphQLReply.run(Self.mutation("pinSession", usage.firstPin.id), on: usage.graph)
        let pinnedAfterRepin = try Self.ids(
            "pinnedSessions", of: await GraphQLReply.run(Self.pinnedQuery, on: usage.graph))
        let unpin = try await GraphQLReply.run(Self.mutation("unpinSession", usage.newest.id), on: usage.graph)
        let pinnedAfterUnpin = try Self.ids(
            "pinnedSessions", of: await GraphQLReply.run(Self.pinnedQuery, on: usage.graph))
        let recentAfterUnpin = try Self.ids(
            "recentSessions", of: await GraphQLReply.run(Self.recentQuery, on: usage.graph))

        #expect(try pin.object("pinSession")["pinned"] as? Bool == true)
        #expect(pinnedAfterPin == Self.ids([usage.firstPin, usage.secondPin, usage.newest]))
        #expect(recentAfterPin == Self.ids([usage.middle, usage.oldest]))
        #expect(pinnedAfterRepin == pinnedAfterPin)
        #expect(try unpin.object("unpinSession")["pinned"] as? Bool == false)
        #expect(pinnedAfterUnpin == Self.ids([usage.firstPin, usage.secondPin]))
        #expect(recentAfterUnpin == Self.ids([usage.newest, usage.middle, usage.oldest]))
    }

    /// The bare verb `pin` is an alias of `pinSession`, and the rewrite
    /// shows in the response (D86).
    @Test("the bare verb pin runs pinSession and reports the rewrite")
    func theBareVerbPinIsAnAlias() async throws {
        let usage = Usage()

        let reply = try await GraphQLReply.run(
            "mutation { pin(input: {id: \"\(usage.newest.id.ulidString)\"}) { id } }", on: usage.graph)

        #expect(reply.rewrote("pin", to: "pinSession"), "messages: \(reply.messages)")
        #expect(try await usage.directory.summary(of: usage.newest.id)?.isPinned == true)
    }

    /// An id that no session has, and a session that an external client does
    /// not own, are `NOT_FOUND`, and nothing is pinned.
    @Test("pinSession of an unknown or a not-owned session is NOT_FOUND and pins nothing")
    func pinSessionOfANotOwnedSessionIsNotFound() async throws {
        let usage = Usage()
        let viewer = GraphQLViewer.external(started: [usage.newest.id.ulidString])

        let unknown = try await GraphQLReply.run(Self.mutation("pinSession", ULID()), on: usage.graph)
        let notOwned = try await GraphQLReply.run(
            Self.mutation("pinSession", usage.newest.id), viewer: viewer, on: usage.graph)

        #expect(unknown.codes == ["NOT_FOUND"], "messages: \(unknown.messages)")
        #expect(notOwned.codes == ["NOT_FOUND"], "messages: \(notOwned.messages)")
        #expect(try await usage.directory.summary(of: usage.newest.id)?.isPinned == false)
    }
    /// `unreadableFolders` gives the path of each recording root that the directory cannot list
    /// (Testudo ^zzfv6c6), and the lists still give the other sessions.
    @Test func theUnreadableFoldersAreNamed() async throws {
        let backing = InMemorySessionDirectory(now: { Self.time(1_000) })
        let pinned = Fixtures.summary(title: "Pinned", pinnedAt: Self.time(10))
        backing.register(pinned)
        let root = URL(fileURLWithPath: "/private/tmp/other-app/.testudo/transcripts", isDirectory: true)
        let graph = SessionsGraph.endpoint(
            of: ForwardingSessionDirectory(backing: backing, unreadableRoots: [root]))

        let reply = try await GraphQLReply.run("{ unreadableFolders pinnedSessions { id } }", on: graph)

        #expect(reply.data?["unreadableFolders"] as? [String] == [root.path])
        #expect(try Self.ids("pinnedSessions", of: reply) == Self.ids([pinned]))
    }

    /// A directory that can list each root gives no unreadable folder.
    @Test func aDirectoryWithNoUnreadableRootGivesNone() async throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory(now: { Self.time(1_000) }))

        let reply = try await GraphQLReply.run("{ unreadableFolders }", on: graph)

        #expect(reply.data?["unreadableFolders"] as? [String] == [])
    }
}
