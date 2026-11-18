// `SessionsGraphPageTests` — the behavioral suite of the `sessionPage` query
// of the `sessions` GraphQL endpoint (D199, task `^61ebsn2`).
//
// Each case registers its sessions in its own `InMemorySessionDirectory`, and
// reads them in pages through `SessionsGraph`. Each session id has its own
// second, so the id order is known before the read. No case reads a
// clock or waits.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for `Query.sessionPage`: each session that is not
/// archived in pages, in the order of the session ids, with the visibility of
/// each viewer kind.
@Suite("SessionsGraphPageTests")
struct SessionsGraphPageTests {

    // MARK: - Constants

    /// The number of sessions of the large cases.
    private static let crowdSize = 250

    /// The page size of the large cases: the most that a filter can ask for.
    private static let largePageSize = 100

    /// The page size of the small cases.
    private static let smallPageSize = 2

    /// The `sessionPage` query with a filter and a cursor.
    private static let pageQuery =
        "query($filter: SessionFilter, $after: String) { sessionPage(filter: $filter, after: $after) "
        + "{ sessions { id } nextCursor } }"

    /// The `sessionPage` query, with the short id and the slug of each
    /// session.
    private static let namesPageQuery = "{ sessionPage { sessions { shortId slug } } }"

    /// The title of the session of the names case.
    private static let apiTitle = "Fix the API tests"

    /// The slug of ``apiTitle``.
    private static let apiSlug = "fix-the-api-tests"

    /// The `sessions` query with a filter.
    private static let sessionsQuery = "query($filter: SessionFilter) { sessions(filter: $filter) { id } }"

    /// The client ID of the archive of a case: a device of the user.
    private static let deviceClientId = "client-device"

    // MARK: - Helpers

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// One page of a `sessionPage` response.
    private struct Page {
        /// The session ids of the page, in order.
        let ids: [String]

        /// The cursor of the next page, or `nil` on the last page.
        let nextCursor: String?
    }

    /// A live root session whose id has the time `offset` seconds after the
    /// fixed time of the fixtures, so the id order is the offset order. A
    /// whole second keeps the millisecond of the id exact.
    ///
    /// - Parameters:
    ///   - offset: The seconds after the fixed time.
    ///   - starter: The session that started this session, or `nil`.
    /// - Returns: The summary.
    private static func session(at offset: Int, startedBy starter: ULID? = nil) -> SessionSummary {
        let time = Fixtures.fixedDate.addingTimeInterval(TimeInterval(offset))
        return Fixtures.summary(id: ULID(timestamp: time), startedBy: starter)
    }

    /// Registers `count` live root sessions, one each second from `first`, in
    /// `directory`.
    ///
    /// - Parameters:
    ///   - count: The number of sessions.
    ///   - first: The second of the first session.
    ///   - directory: The directory.
    /// - Returns: The id of each session, in id order.
    @discardableResult
    private static func registerSessions(
        _ count: Int, from first: Int = 0, in directory: InMemorySessionDirectory
    ) -> [String] {
        (first..<first + count).map { offset in
            let summary = session(at: offset)
            directory.register(summary)
            return summary.id.ulidString
        }
    }

    /// A filter that also finds the sessions that are not live, with a page
    /// size.
    ///
    /// - Parameter limit: The page size.
    /// - Returns: The filter.
    private static func recordedFilter(limit: Int) -> Map {
        ["includeRecorded": true, "limit": .number(Number(limit))]
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

    /// Reads one page.
    ///
    /// - Parameters:
    ///   - cursor: The cursor of the page, or `nil` for the first page.
    ///   - filter: The filter, or no filter.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The page.
    /// - Throws: What ``run(_:variables:viewer:on:)`` throws, or an error when
    ///   the response has no page.
    private static func page(
        after cursor: String?, filter: Map, viewer: GraphQLViewer?, on graph: SessionsGraph
    ) async throws -> Page {
        let variables: [String: Map] = ["filter": filter, "after": cursor.map(Map.string) ?? .null]
        let reply = try await run(pageQuery, variables: variables, viewer: viewer, on: graph)
        let object = try reply.object("sessionPage")
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        return Page(ids: sessions.compactMap { $0["id"] as? String }, nextCursor: object["nextCursor"] as? String)
    }

    /// Reads each page from a cursor to the last page, and gives each page.
    ///
    /// - Parameters:
    ///   - cursor: The cursor of the first page to read, or `nil` for the
    ///     first page of all.
    ///   - filter: The filter, or no filter.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The pages, in order.
    /// - Throws: What ``page(after:filter:viewer:on:)`` throws, or an error
    ///   when the read does not end after more pages than sessions.
    private static func pages(
        after cursor: String? = nil, filter: Map = .null, viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> [Page] {
        var pages: [Page] = []
        var next = cursor
        // A loop and not a `map`: each page needs the cursor of the page
        // before. The bound stops a cursor that never ends.
        for _ in 0...crowdSize + 1 {
            let page = try await page(after: next, filter: filter, viewer: viewer, on: graph)
            pages.append(page)
            next = page.nextCursor
            if next == nil {
                return pages
            }
        }
        Issue.record("The read did not end after \(crowdSize + 1) pages.")
        return pages
    }

    /// The id of each session of each page, in order.
    ///
    /// - Parameter pages: The pages.
    /// - Returns: The ids.
    private static func ids(of pages: [Page]) -> [String] {
        pages.flatMap(\.ids)
    }

    // MARK: - Pages

    /// With 250 sessions and a page size of 100, the client reads each
    /// session one time, in the order of the session ids.
    @Test("the pages give each of 250 sessions one time, in id order")
    func thePagesGiveEachSessionOneTime() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.crowdSize, in: directory)

        let pages = try await Self.pages(
            filter: ["limit": .number(Number(Self.largePageSize))], on: SessionsGraph.endpoint(of: directory))

        #expect(Self.ids(of: pages) == registered)
    }

    /// The page size of the filter cuts each page: 250 sessions in pages of
    /// 100 are three pages.
    @Test("the page size of the filter cuts each page")
    func thePageSizeCutsEachPage() async throws {
        let directory = InMemorySessionDirectory()
        Self.registerSessions(Self.crowdSize, in: directory)

        let pages = try await Self.pages(
            filter: ["limit": .number(Number(Self.largePageSize))], on: SessionsGraph.endpoint(of: directory))

        let lastPageSize = Self.crowdSize - 2 * Self.largePageSize
        #expect(pages.map(\.ids.count) == [Self.largePageSize, Self.largePageSize, lastPageSize])
    }

    /// A last page that is full has no next cursor: the client does not read
    /// an empty page after it.
    @Test("a full last page has no next cursor")
    func aFullLastPageHasNoNextCursor() async throws {
        let directory = InMemorySessionDirectory()
        Self.registerSessions(Self.smallPageSize, in: directory)

        let pages = try await Self.pages(
            filter: ["limit": .number(Number(Self.smallPageSize))], on: SessionsGraph.endpoint(of: directory))

        #expect(pages.count == 1)
    }

    /// A session that starts after the first page has a newer id than each
    /// session before it, thus the read gives each session one time, and the
    /// new session last.
    @Test("a session that starts during the read shows one time, and no session is lost")
    func aSessionThatStartsDuringTheReadShowsOneTime() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.crowdSize, in: directory)
        let graph = SessionsGraph.endpoint(of: directory)
        let filter: Map = ["limit": .number(Number(Self.largePageSize))]
        let first = try await Self.page(after: nil, filter: filter, viewer: nil, on: graph)

        let started = Self.registerSessions(1, from: Self.crowdSize, in: directory)
        let rest = try await Self.pages(after: first.nextCursor, filter: filter, on: graph)

        #expect(first.ids + Self.ids(of: rest) == registered + started)
    }

    /// With `includeRecorded`, the pages give each session that is not
    /// archived, and no archived session.
    @Test("an archived session is not in the pages")
    func anArchivedSessionIsNotInThePages() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.smallPageSize * 2, in: directory)
        let archived = try #require(registered.first)
        _ = try await directory.archive(
            try #require(ULID(ulidString: archived)), by: .user(clientID: Self.deviceClientId))

        let pages = try await Self.pages(
            filter: Self.recordedFilter(limit: Self.smallPageSize), on: SessionsGraph.endpoint(of: directory))

        #expect(Self.ids(of: pages) == Array(registered.dropFirst()))
    }

    /// A filter with the state `ARCHIVED` asks for the archived sessions:
    /// the pages give them.
    @Test("the state ARCHIVED gives the archived sessions in the pages")
    func theArchivedStateGivesTheArchivedSessions() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.smallPageSize * 2, in: directory)
        let archived = try #require(registered.first)
        _ = try await directory.archive(
            try #require(ULID(ulidString: archived)), by: .user(clientID: Self.deviceClientId))

        let pages = try await Self.pages(
            filter: ["state": "ARCHIVED", "limit": .number(Number(Self.smallPageSize))],
            on: SessionsGraph.endpoint(of: directory))

        #expect(Self.ids(of: pages) == [archived])
    }

    /// An external viewer that owns one session gets, on each page, only that
    /// session and the sessions that it started, and none of the 250
    /// sessions with no link to it, also when they come first in id order.
    @Test("an external viewer gets only the sessions that it can see, on each page")
    func anExternalViewerGetsOnlyVisibleSessions() async throws {
        let directory = InMemorySessionDirectory()
        Self.registerSessions(Self.crowdSize, in: directory)
        let owned = Self.session(at: Self.crowdSize)
        let started = (1...Self.smallPageSize + 1).map { Self.session(at: Self.crowdSize + $0, startedBy: owned.id) }
        for summary in [owned] + started {
            directory.register(summary)
        }
        let viewer = GraphQLViewer.external(owning: [owned.id.ulidString])

        let pages = try await Self.pages(
            filter: ["limit": .number(Number(Self.smallPageSize))], viewer: viewer,
            on: SessionsGraph.endpoint(of: directory))

        #expect(Self.ids(of: pages) == ([owned] + started).map(\.id.ulidString))
    }

    /// The `sessions` query keeps its answer: the newest first, cut at the
    /// default limit of 50.
    @Test("the sessions query still gives the newest sessions first")
    func theSessionsQueryKeepsItsAnswer() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.crowdSize, in: directory)

        let reply = try await Self.run(
            Self.sessionsQuery, variables: ["filter": .null], on: SessionsGraph.endpoint(of: directory))

        let ids = try reply.list("sessions").compactMap { $0["id"] as? String }
        #expect(ids == Array(registered.reversed().prefix(SessionsGraphResolver.defaultListLimit)))
    }

    /// Each session of a page has its short id and its slug.
    @Test("sessionPage gives the shortId and the slug of each session")
    func aPageGivesTheShortIDAndTheSlug() async throws {
        let directory = InMemorySessionDirectory()
        let session = Fixtures.summary(title: Self.apiTitle)
        directory.register(session)

        let reply = try await Self.run(Self.namesPageQuery, on: SessionsGraph.endpoint(of: directory))
        let sessions = try #require(try reply.object("sessionPage")["sessions"] as? [[String: Any]])

        #expect(sessions.first?["shortId"] as? String == session.shortID)
        #expect(sessions.first?["slug"] as? String == Self.apiSlug)
    }

    // MARK: - The cursor

    /// A cursor that is not a session id gives `INVALID_CURSOR`.
    @Test("a cursor that is not a session id gives INVALID_CURSOR")
    func aMalformedCursorGivesInvalidCursor() async throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let reply = try await Self.run(
            Self.pageQuery, variables: ["filter": .null, "after": "not-a-cursor"], on: graph)

        #expect(reply.codes == ["INVALID_CURSOR"])
    }

    /// The cursor reads a session id in lower case.
    @Test("the cursor reads a session id in lower case")
    func theCursorReadsALowerCaseID() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.smallPageSize, in: directory)
        let cursor = try #require(registered.first).lowercased()

        let pages = try await Self.pages(after: cursor, on: SessionsGraph.endpoint(of: directory))

        #expect(Self.ids(of: pages) == Array(registered.dropFirst()))
    }

    // MARK: - Aliases and conventions

    /// The alias tables take `sessionsPage` for `sessionPage`, `cursor` for
    /// its `after`, and `items` and `endCursor` for the fields of a page, and
    /// the response tells each rewrite in `extensions.rewrites`.
    @Test("the aliases of sessionPage work and show in extensions.rewrites")
    func theAliasesOfSessionPageWork() async throws {
        let directory = InMemorySessionDirectory()
        let registered = Self.registerSessions(Self.smallPageSize, in: directory)
        let cursor = try #require(registered.first)

        let reply = try await Self.run(
            "{ sessionsPage(cursor: \"\(cursor)\") { items { id } endCursor } }",
            on: SessionsGraph.endpoint(of: directory))

        let page = try reply.object("sessionsPage")
        #expect(try #require(page["items"] as? [[String: Any]]).compactMap { $0["id"] as? String } == [registered[1]])
        #expect(reply.rewrote("sessionsPage", to: "sessionPage"))
        #expect(reply.rewrote("cursor", to: "after"))
        #expect(reply.rewrote("items", to: "sessions"))
        #expect(reply.rewrote("endCursor", to: "nextCursor"))
    }

    /// The endpoint with `sessionPage` still conforms to the conventions of
    /// EXTRAS-9, with the `sessionsPage` alias probe.
    @Test("the endpoint conforms, with the sessionsPage alias probe")
    func theEndpointConformsWithTheSessionsPageProbe() async throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())
        let probes = [
            GraphQLAliasProbe(query: "{ sessionsPage { nextCursor } }", from: "sessionsPage", to: "sessionPage")
        ]

        let problems = await GraphQLEndpointConformance.problems(
            of: graph, scope: .server, probes: probes, codes: SessionsRefusal.codes, clock: ManualRunClock())

        #expect(problems.isEmpty, "problems: \(problems)")
    }
}
