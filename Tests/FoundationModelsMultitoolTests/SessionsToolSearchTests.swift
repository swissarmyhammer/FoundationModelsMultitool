// `SessionsToolSearchTests` — the `search sessions` operation of the
// `sessions` tool (D207 (d), (e), (g)).
//
// Each case uses its own `InMemorySessionDirectory` and a fake searcher that
// gives a fixed page and records each request. A case reads the request that
// the operation made, or the text of the answer. No case waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `search sessions` operation of ``SessionsTool``.
@Suite("SessionsToolSearchTests", .ownsTemporaryDirectories)
struct SessionsToolSearchTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of the operation.
    private static let searchOp = "search sessions"

    /// The query of most cases.
    private static let queryText = "retry budget"

    /// The title of the session that the answer cases find.
    private static let foundTitle = "Retry budget"

    /// The last line of each answer: the limit of the search (D207 (d)).
    private static let limitLine = """
        The search covers only the sessions that this server records, not the sessions of other agents such as \
        Claude Code or Codex.
        """

    /// The words of the corrective of a server with no searcher.
    private static let noSearcherWords = "Search (⌘F)"

    /// The words of the corrective of a reference that names two sessions.
    private static let ambiguousWords = "names more than one session"

    /// A folder that is not the folder of the caller.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// The limit of a call that names none.
    private static let defaultLimit = 20

    /// The largest limit of a call.
    private static let largestLimit = 50

    /// A limit over ``largestLimit``.
    private static let tooLargeLimit = 99

    /// A tag of the tag cases.
    private static let tag = "release"

    /// An agent of the agent cases, which is not ``SessionsToolFixtures/agentID``.
    private static let otherAgent = "reviewer"

    /// A date token with a month that does not exist.
    private static let wrongDateToken = "after:2026-13-01"

    /// The number of hits of the session of the answer cases.
    private static let hitCount = 4

    /// The snippets of the hits of the answer cases, the best hit first.
    private static let snippets = ["the retry budget is 3", "raise the budget", "keep it", "a fourth hit"]

    /// The authors of the hits of the answer cases.
    private static let authors = ["user", "agent", "user", "agent"]

    // MARK: - Helpers

    /// Calls `search sessions` as the caller, in the folder
    /// ``SessionsToolFixtures/workingFolder``.
    ///
    /// - Parameters:
    ///   - fields: The fields of the operation.
    ///   - searcher: The searcher of the tool, or `nil` for none.
    ///   - directory: The directory of the tool.
    ///   - op: The op string. ``searchOp`` when not given.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ fields: [(String, any ConvertibleToGeneratedContent)],
        searcher: (any SessionTranscriptSearcher)?,
        in directory: InMemorySessionDirectory = InMemorySessionDirectory(),
        op: String = searchOp
    ) async throws -> String {
        let tool = try SessionsTool(directory: directory, searcher: searcher)
        return try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload(op, fields))
        }
    }

    /// The one request that `searcher` got.
    ///
    /// - Parameter searcher: The searcher.
    /// - Returns: The request.
    /// - Throws: An error when the searcher got no request.
    private static func onlyRequest(of searcher: RecordingTranscriptSearcher) async throws -> SessionSearchRequest {
        try #require(await searcher.requests.first)
    }

    /// Searches `query` as the caller, with a searcher that finds nothing,
    /// and gives the request of the search.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - fields: The other fields of the operation.
    ///   - directory: The directory of the tool.
    /// - Returns: The request.
    /// - Throws: An error when the searcher got no request.
    private static func request(
        of query: String = queryText, _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        in directory: InMemorySessionDirectory = InMemorySessionDirectory()
    ) async throws -> SessionSearchRequest {
        let searcher = RecordingTranscriptSearcher()
        _ = try await callAsCaller([("query", query)] + fields, searcher: searcher, in: directory)
        return try await onlyRequest(of: searcher)
    }

    /// The hits of the answer cases.
    ///
    /// - Returns: One hit for each of ``snippets``.
    private static func hits() -> [SessionSearchHit] {
        zip(authors, snippets).map { author, snippet in
            SessionSearchHit(
                entryID: snippet, kind: .agent, author: author, date: Fixtures.fixedDate, snippet: snippet, ranges: [],
                terms: [])
        }
    }

    /// A page with one result for `session`.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - hits: The hits of the result.
    /// - Returns: The page.
    private static func page(of session: ULID, hits: [SessionSearchHit]) -> SessionSearchPage {
        SessionSearchPage(
            sessions: [SessionSearchResult(session: session, score: 1, hitCount: hitCount, hits: hits)],
            nextCursor: nil, unavailableFolders: [])
    }

    /// The day of `date` as the answer gives it: `YYYY-MM-DD` in the time
    /// zone of the server.
    ///
    /// - Parameter date: The date.
    /// - Returns: The day.
    private static func day(of date: Date) -> String {
        Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(date)
    }

    // MARK: - The answer

    @Test("search sessions gives one line for each session, at most three hits, and the limit line")
    func theAnswerListsEachSessionAndItsHits() async throws {
        let directory = InMemorySessionDirectory()
        let found = Fixtures.summary(title: Self.foundTitle)
        directory.register(found)
        let searcher = RecordingTranscriptSearcher(page: Self.page(of: found.id, hits: Self.hits()))

        let output = try await Self.callAsCaller([("query", Self.queryText)], searcher: searcher, in: directory)

        let expected = """
            @\(found.shortID) \(Self.foundTitle) (\(Fixtures.workingFolder.path)) \(Self.day(of: Fixtures.fixedDate)) \
            – \(Self.hitCount) hits
              user: the retry budget is 3
              agent: raise the budget
              user: keep it
            \(Self.limitLine)
            """
        #expect(output == expected)
    }

    @Test("a hit with no author gives the kind of its entry in place of the author")
    func aHitWithNoAuthorGivesItsKind() async throws {
        let directory = InMemorySessionDirectory()
        let found = Fixtures.summary(title: Self.foundTitle)
        directory.register(found)
        let hit = SessionSearchHit(
            entryID: "tool-1", kind: .tool, author: nil, date: Fixtures.fixedDate, snippet: "swift test", ranges: [],
            terms: [])
        let searcher = RecordingTranscriptSearcher(page: Self.page(of: found.id, hits: [hit]))

        let output = try await Self.callAsCaller([("query", Self.queryText)], searcher: searcher, in: directory)

        #expect(output.contains("\n  tool: swift test\n"), "output was: \(output)")
    }

    @Test("search sessions with no hit gives the query and the limit line")
    func theAnswerWithNoHitGivesTheQuery() async throws {
        let output = try await Self.callAsCaller(
            [("query", Self.queryText)], searcher: RecordingTranscriptSearcher())

        #expect(output == "No session matches the query \"\(Self.queryText)\".\n\(Self.limitLine)")
    }

    @Test("search sessions on a server with no searcher gives the corrective that names Search (⌘F)")
    func noSearcherGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller([("query", Self.queryText)], searcher: nil)

        #expect(output.contains(Self.noSearcherWords), "output was: \(output)")
    }

    @Test("a tool with no searcher uses the searcher that the endpoint of its directory keeps")
    func theEndpointKeepsTheSearcher() async throws {
        let directory = InMemorySessionDirectory()
        let searcher = RecordingTranscriptSearcher()
        let endpoint = SessionsGraph.endpoint(of: directory, searcher: searcher)

        _ = try await Self.callAsCaller([("query", Self.queryText)], searcher: nil, in: directory)

        #expect(await searcher.requests.count == 1)
        withExtendedLifetime(endpoint) {}
    }

    @Test("the verb grep is an alias of search")
    func grepIsAnAliasOfSearch() async throws {
        let searcher = RecordingTranscriptSearcher()

        _ = try await Self.callAsCaller([("query", Self.queryText)], searcher: searcher, op: "grep sessions")

        #expect(await searcher.requests.count == 1)
    }

    // MARK: - archived

    @Test("search sessions with no archived argument does not include the archived sessions")
    func noArchivedArgumentExcludesTheArchived() async throws {
        #expect(try await Self.request().includeArchived == false)
    }

    @Test("search sessions with archived true includes the archived sessions")
    func archivedTrueIncludesTheArchived() async throws {
        #expect(try await Self.request([("archived", true)]).includeArchived)
    }

    @Test("the token is:archived includes the archived sessions")
    func theArchivedTokenIncludesTheArchived() async throws {
        #expect(try await Self.request(of: "budget is:archived").includeArchived)
    }

    // MARK: - limit

    @Test("search sessions with no limit asks for 20 sessions")
    func noLimitAsksForTheDefault() async throws {
        #expect(try await Self.request().limit == Self.defaultLimit)
    }

    @Test("search sessions with a limit over 50 asks for 50 sessions")
    func aLargeLimitIsCappedAt50() async throws {
        #expect(try await Self.request([("limit", Self.tooLargeLimit)]).limit == Self.largestLimit)
    }

    // MARK: - The session filter

    @Test("search sessions with no session token and no folder gives no session filter")
    func noTokenGivesNoFilter() async throws {
        #expect(try await Self.request().sessions == nil)
    }

    @Test("the folder argument keeps the sessions of that folder")
    func theFolderArgumentKeepsItsSessions() async throws {
        let directory = InMemorySessionDirectory()
        let inFolder = Fixtures.summary(folder: Self.otherFolder)
        directory.register(inFolder)
        directory.register(Fixtures.summary())

        let request = try await Self.request([("folder", Self.otherFolder.path)], in: directory)

        #expect(request.sessions == [inFolder.id])
    }

    @Test("the token folder:. keeps the sessions of the folder of the caller")
    func theDotFolderTokenKeepsTheCallerFolder() async throws {
        let directory = InMemorySessionDirectory()
        directory.register(Fixtures.summary(folder: Self.otherFolder))

        let request = try await Self.request(of: "budget folder:.", in: directory)

        let callerFolderSessions = try await directory.sessions(
            matching: SessionQuery(workingDirectory: Fixtures.workingFolder, includesRecorded: true))
        #expect(request.sessions == Set(callerFolderSessions.map(\.id)))
    }

    @Test("the tag token keeps the sessions with that tag")
    func theTagTokenKeepsItsSessions() async throws {
        let directory = InMemorySessionDirectory()
        let tagged = Fixtures.summary(tags: [Self.tag])
        directory.register(tagged)
        directory.register(Fixtures.summary())

        let request = try await Self.request(of: "budget #\(Self.tag)", in: directory)

        #expect(request.sessions == [tagged.id])
    }

    @Test("the agent token keeps the sessions of that agent")
    func theAgentTokenKeepsItsSessions() async throws {
        let directory = InMemorySessionDirectory()
        let ofAgent = Fixtures.summary(agent: Self.otherAgent)
        directory.register(ofAgent)
        directory.register(Fixtures.summary())

        let request = try await Self.request(of: "budget agent:\(Self.otherAgent)", in: directory)

        #expect(request.sessions == [ofAgent.id])
    }

    @Test("the token @<slug> keeps the session that the resolver names")
    func theSlugTokenKeepsItsSession() async throws {
        let directory = InMemorySessionDirectory()
        let named = Fixtures.summary(title: Self.foundTitle)
        directory.register(named)
        directory.register(Fixtures.summary())

        let request = try await Self.request(of: "budget @\(named.slug)", in: directory)

        #expect(request.sessions == [named.id])
    }

    @Test("a token @<slug> that names two sessions gives the ambiguous corrective and does not search")
    func anAmbiguousSlugIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let first = Fixtures.summary(title: Self.foundTitle)
        directory.register(first)
        directory.register(Fixtures.summary(title: Self.foundTitle))
        let searcher = RecordingTranscriptSearcher()

        let output = try await Self.callAsCaller(
            [("query", "budget @\(first.slug)")], searcher: searcher, in: directory)

        #expect(output.contains(Self.ambiguousWords), "output was: \(output)")
        #expect(await searcher.requests.isEmpty)
    }

    // MARK: - The preferred folder

    @Test("the preferred folder of the search is the folder of the caller session")
    func thePreferredFolderIsTheCallerFolder() async throws {
        #expect(try await Self.request().preferredFolder == Fixtures.workingFolder)
    }

    // MARK: - A wrong query

    @Test("a wrong date in the query gives the corrective that names the token and does not search")
    func aWrongDateIsACorrective() async throws {
        let searcher = RecordingTranscriptSearcher()

        let output = try await Self.callAsCaller(
            [("query", "budget \(Self.wrongDateToken)")], searcher: searcher)

        #expect(output.contains(Self.wrongDateToken), "output was: \(output)")
        #expect(await searcher.requests.isEmpty)
    }
}
