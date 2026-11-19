// `SessionsGraphSearchTests` — the `searchSessions` field of the `sessions`
// GraphQL endpoint (D207 (d), (h), task `^c5dkdc6`).
//
// Each case registers its sessions in its own `InMemorySessionDirectory`,
// gives the endpoint of that directory a fake searcher or no searcher, and
// reads the field with one viewer. The fake searcher gives a fixed page and
// records each request. No case reads a clock or waits.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `searchSessions` field of ``SessionsGraph``.
@Suite("SessionsGraphSearchTests")
struct SessionsGraphSearchTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The query of most cases.
    private static let queryText = "retry budget"

    /// The title of the found session.
    private static let foundTitle = "Retry budget"

    /// The title of the found session after a rename.
    private static let renamedTitle = "Retry budget, second pass"

    /// The score of the found session.
    private static let score = 0.75

    /// The number of hits of the found session.
    private static let hitCount = 7

    /// The wire id of the entry of the transcript hit.
    private static let entryID = "turn-3/agent-1"

    /// The snippet of the transcript hit.
    private static let snippet = "the retry budget is 3"

    /// The author of the transcript hit.
    private static let author = "agent"

    /// The start of the matched words in ``snippet``.
    private static let rangeStart = 4

    /// The end of the matched words in ``snippet``.
    private static let rangeEnd = 16

    /// The matched words of the transcript hit.
    private static let terms = ["retry", "budget"]

    /// The cursor of the next page that the fake searcher gives.
    private static let nextCursor = "page-2"

    /// The folder that the fake searcher cannot read.
    private static let unavailableFolder = URL(fileURLWithPath: "/work/project")

    /// The folder of the tab of the client.
    private static let tabFolder = "/work/tab"

    /// The limit of a call that names `first`.
    private static let firstLimit = 5

    /// The full document of the field: each field of each new type.
    private static let fullQuery = """
        query($query: String!) {
          searchSessions(query: $query) {
            nextCursor
            unavailableFolders
            results {
              session { id title }
              score
              hitCount
              hits { entryId kind author at snippet ranges { start end } terms }
            }
          }
        }
        """

    /// The document that reads only the session ids of the results.
    private static let idsQuery = """
        query($query: String!) { searchSessions(query: $query) { results { session { id } } } }
        """

    /// The document that names one session and the limit.
    private static let oneSessionQuery = """
        query($query: String!, $session: ID!, $first: Int!) {
          searchSessions(query: $query, session: $session, first: $first) { results { hitCount } }
        }
        """

    /// The document that names the folder of the tab and a cursor.
    private static let folderQuery = """
        query($query: String!, $folder: String!, $after: String!) {
          searchSessions(query: $query, folder: $folder, after: $after) { nextCursor }
        }
        """

    /// The document that names the archived sessions.
    private static let archivedQuery = """
        query($query: String!) { searchSessions(query: $query, archived: true) { nextCursor } }
        """

    /// The document that reads the unavailable folders.
    private static let foldersQuery = """
        query($query: String!) { searchSessions(query: $query) { unavailableFolders } }
        """

    /// The document with the aliases of the arguments and of the fields.
    private static let aliasQuery = """
        { searchSessions(text: "retry budget", limit: 5) { items { session { id } } endCursor } }
        """

    // MARK: - Helpers

    /// The sessions of one case in their own directory, and the endpoint of
    /// that directory with its searcher.
    private struct Setup {
        /// The directory of the sessions.
        let directory = InMemorySessionDirectory()

        /// The found session.
        let found: SessionSummary

        /// A second found session, which an external viewer does not own.
        let other: SessionSummary

        /// The fake searcher, or `nil` for an endpoint with no searcher.
        let searcher: RecordingTranscriptSearcher?

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Registers two sessions, and gives the endpoint a searcher that
        /// finds both, or no searcher.
        ///
        /// - Parameter hasSearcher: False for an endpoint with no searcher.
        init(hasSearcher: Bool = true) {
            found = Fixtures.summary(title: SessionsGraphSearchTests.foundTitle)
            other = Fixtures.summary(folder: URL(fileURLWithPath: SessionsGraphSearchTests.tabFolder))
            directory.register(found)
            directory.register(other)
            let page = SessionSearchPage(
                sessions: [
                    SessionsGraphSearchTests.result(of: found.id), SessionsGraphSearchTests.result(of: other.id),
                ],
                nextCursor: SessionsGraphSearchTests.nextCursor,
                unavailableFolders: [SessionsGraphSearchTests.unavailableFolder])
            searcher = hasSearcher ? RecordingTranscriptSearcher(page: page) : nil
            graph = SessionsGraph.endpoint(of: directory, searcher: searcher)
        }

        /// Runs `document` with ``queryText`` as the `query` variable.
        ///
        /// - Parameters:
        ///   - document: The GraphQL document.
        ///   - variables: The other variables of the document.
        ///   - viewer: The client of the call, or `nil` for the agent.
        /// - Returns: The response.
        /// - Throws: What the endpoint throws.
        func run(
            _ document: String, variables: [String: Map] = [:], viewer: GraphQLViewer? = nil
        ) async throws -> GraphQLReply {
            try await GraphQLReply.run(
                document,
                variables: variables.merging(["query": .string(SessionsGraphSearchTests.queryText)]) {
                    own, _ in own
                }, viewer: viewer, on: graph)
        }

        /// The one request that the searcher got.
        ///
        /// - Returns: The request.
        /// - Throws: An error when the setup has no searcher or the searcher
        ///   got no request.
        func onlyRequest() async throws -> SessionSearchRequest {
            let searcher = try #require(searcher)
            return try #require(await searcher.requests.first)
        }
    }

    /// The result of one session: a transcript hit and a `SESSION` hit.
    ///
    /// - Parameter id: The id of the session.
    /// - Returns: The result.
    private static func result(of id: ULID) -> SessionSearchResult {
        SessionSearchResult(
            session: id, score: score, hitCount: hitCount,
            hits: [
                SessionSearchHit(
                    entryID: entryID, kind: .agent, author: author, date: Fixtures.fixedDate, snippet: snippet,
                    ranges: [rangeStart..<rangeEnd], terms: terms),
                SessionSearchHit(
                    entryID: id.ulidString, kind: .session, author: nil, date: nil, snippet: foundTitle,
                    ranges: [], terms: []),
            ])
    }

    /// The first result of a response of ``fullQuery``.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The result.
    /// - Throws: An error when the response has no result.
    private static func firstResult(of reply: GraphQLReply) throws -> [String: Any] {
        let results = try #require(try reply.object("searchSessions")["results"] as? [[String: Any]])
        return try #require(results.first, "errors: \(reply.messages)")
    }

    /// The hits of the first result of a response of ``fullQuery``.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The hits.
    /// - Throws: An error when the response has no hit.
    private static func firstHits(of reply: GraphQLReply) throws -> [[String: Any]] {
        try #require(try firstResult(of: reply)["hits"] as? [[String: Any]])
    }

    /// The session ids of the results of a response.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The ids, in the order of the results.
    /// - Throws: An error when the response has no result list.
    private static func resultIDs(of reply: GraphQLReply) throws -> [String] {
        let results = try #require(try reply.object("searchSessions")["results"] as? [[String: Any]])
        return results.compactMap { ($0["session"] as? [String: Any])?["id"] as? String }
    }

    // MARK: - The results

    @Test("searchSessions gives the score of each result")
    func searchSessionsGivesTheScore() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.fullQuery)

        #expect(try Self.firstResult(of: reply)["score"] as? Double == Self.score)
    }

    @Test("searchSessions gives the hit count of each result")
    func searchSessionsGivesTheHitCount() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.fullQuery)

        #expect(try Self.firstResult(of: reply)["hitCount"] as? Int == Self.hitCount)
    }

    @Test("searchSessions gives the entry id, the kind, the author and the snippet of a hit")
    func searchSessionsGivesTheFactsOfAHit() async throws {
        let setup = Setup()

        let hit = try #require(try Self.firstHits(of: try await setup.run(Self.fullQuery)).first)

        #expect(
            [hit["entryId"], hit["kind"], hit["author"], hit["snippet"]] as? [String]
                == [Self.entryID, "AGENT", Self.author, Self.snippet])
    }

    @Test("searchSessions gives the date of a hit as a DateTime")
    func searchSessionsGivesTheDateOfAHit() async throws {
        let setup = Setup()

        let hit = try #require(try Self.firstHits(of: try await setup.run(Self.fullQuery)).first)

        #expect(hit["at"] as? String == DateTime(Fixtures.fixedDate).rfc3339)
    }

    @Test("searchSessions gives the ranges of the matched words of a hit")
    func searchSessionsGivesTheRanges() async throws {
        let setup = Setup()

        let hit = try #require(try Self.firstHits(of: try await setup.run(Self.fullQuery)).first)

        let ranges = try #require(hit["ranges"] as? [[String: Int]])
        #expect(ranges == [["start": Self.rangeStart, "end": Self.rangeEnd]])
    }

    @Test("searchSessions gives the matched words of a hit")
    func searchSessionsGivesTheTerms() async throws {
        let setup = Setup()

        let hit = try #require(try Self.firstHits(of: try await setup.run(Self.fullQuery)).first)

        #expect(hit["terms"] as? [String] == Self.terms)
    }

    @Test("searchSessions gives a SESSION hit with no author, no date, no range and no term")
    func searchSessionsGivesASessionHit() async throws {
        let setup = Setup()

        let hit = try #require(try Self.firstHits(of: try await setup.run(Self.fullQuery)).last)

        #expect(hit["kind"] as? String == "SESSION")
        #expect(hit["author"] is NSNull)
        #expect(hit["at"] is NSNull)
        #expect(hit["ranges"] as? [[String: Int]] == [])
        #expect(hit["terms"] as? [String] == [])
    }

    @Test("searchSessions gives the results in the order of the searcher")
    func searchSessionsKeepsTheOrderOfTheSearcher() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.idsQuery)

        #expect(try Self.resultIDs(of: reply) == [setup.found.id.ulidString, setup.other.id.ulidString])
    }

    @Test("searchSessions gives the next cursor of the searcher")
    func searchSessionsGivesTheNextCursor() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.fullQuery)

        #expect(try reply.object("searchSessions")["nextCursor"] as? String == Self.nextCursor)
    }

    @Test("searchSessions gives the path of each unavailable folder of a visible result")
    func searchSessionsGivesTheUnavailableFolders() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.foldersQuery)

        #expect(
            try reply.object("searchSessions")["unavailableFolders"] as? [String] == [Self.unavailableFolder.path])
    }

    // MARK: - The session of a result

    @Test("the session of a result gives the facts of the directory")
    func theSessionOfAResultGivesTheFactsOfTheDirectory() async throws {
        let setup = Setup()

        let session = try #require(
            try Self.firstResult(of: try await setup.run(Self.fullQuery))["session"] as? [String: Any])

        #expect(session["title"] as? String == Self.foundTitle)
    }

    @Test("the session of a result gives the name after a rename")
    func theSessionOfAResultGivesTheNameAfterARename() async throws {
        let setup = Setup()
        _ = try await setup.directory.setTitle(Self.renamedTitle, of: setup.found.id)

        let session = try #require(
            try Self.firstResult(of: try await setup.run(Self.fullQuery))["session"] as? [String: Any])

        #expect(session["title"] as? String == Self.renamedTitle)
    }

    // MARK: - The request

    @Test("searchSessions gives the searcher the parsed query")
    func searchSessionsGivesTheParsedQuery() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.idsQuery)

        #expect(try await setup.onlyRequest().query == SessionSearchQuery(parsing: Self.queryText))
    }

    @Test("searchSessions with no argument asks for 20 sessions, no archived session and the first page")
    func searchSessionsHasTheDefaults() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.idsQuery)

        let request = try await setup.onlyRequest()
        #expect(request.limit == SessionsVisibility.defaultSearchLimit)
        #expect(!request.includeArchived)
        #expect(request.cursor == nil)
        #expect(request.session == nil)
    }

    @Test("searchSessions(session:) asks for each hit of that session, up to first")
    func searchSessionsWithASessionAsksForEachHitOfIt() async throws {
        let setup = Setup()

        _ = try await setup.run(
            Self.oneSessionQuery,
            variables: ["session": .string(setup.found.id.ulidString), "first": .number(Number(Self.firstLimit))])

        let request = try await setup.onlyRequest()
        #expect(request.session == setup.found.id)
        #expect(request.limit == Self.firstLimit)
    }

    @Test("searchSessions(session:) with a text that is not a session id gives INVALID_SESSION_ID")
    func searchSessionsWithAWrongSessionIDGivesTheRefusal() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            Self.oneSessionQuery,
            variables: ["session": .string("not-an-id"), "first": .number(Number(Self.firstLimit))])

        #expect(reply.codes == ["INVALID_SESSION_ID"])
    }

    @Test("searchSessions(folder:) makes the folder of the tab the preferred folder")
    func searchSessionsWithAFolderPrefersIt() async throws {
        let setup = Setup()

        _ = try await setup.run(
            Self.folderQuery, variables: ["folder": .string(Self.tabFolder), "after": .string(Self.nextCursor)])

        #expect(try await setup.onlyRequest().preferredFolder?.path == Self.tabFolder)
    }

    @Test("searchSessions(folder:) gives the folder of the tab to the folder:. token")
    func searchSessionsWithAFolderReadsTheDotToken() async throws {
        let setup = Setup()

        _ = try await GraphQLReply.run(
            Self.folderQuery,
            variables: [
                "query": .string("\(Self.queryText) folder:."), "folder": .string(Self.tabFolder),
                "after": .string(Self.nextCursor),
            ], on: setup.graph)

        #expect(try await setup.onlyRequest().sessions == [setup.other.id])
    }

    @Test("searchSessions(after:) gives the cursor to the searcher")
    func searchSessionsGivesTheCursor() async throws {
        let setup = Setup()

        _ = try await setup.run(
            Self.folderQuery, variables: ["folder": .string(Self.tabFolder), "after": .string(Self.nextCursor)])

        #expect(try await setup.onlyRequest().cursor == Self.nextCursor)
    }

    @Test("searchSessions(archived: true) asks for the archived sessions")
    func searchSessionsWithArchivedAsksForThem() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.archivedQuery)

        #expect(try await setup.onlyRequest().includeArchived)
    }

    // MARK: - The visibility

    @Test("an external viewer gets only the results of the sessions that it can see")
    func anExternalViewerGetsOnlyItsSessions() async throws {
        let setup = Setup()
        let viewer = GraphQLViewer.external(owning: [setup.found.id.ulidString])

        let reply = try await setup.run(Self.idsQuery, viewer: viewer)

        #expect(try Self.resultIDs(of: reply) == [setup.found.id.ulidString])
    }

    @Test("an external viewer gets no unavailable folder of a session that it cannot see")
    func anExternalViewerGetsNoHiddenFolder() async throws {
        let setup = Setup()
        let viewer = GraphQLViewer.external(owning: [setup.other.id.ulidString])

        let reply = try await setup.run(Self.foldersQuery, viewer: viewer)

        #expect(try reply.object("searchSessions")["unavailableFolders"] as? [String] == [])
    }

    // MARK: - The refusals

    @Test("searchSessions on an endpoint with no searcher gives MISSING_SEARCHER with the corrective of the tool")
    func searchSessionsWithNoSearcherGivesTheRefusal() async throws {
        let setup = Setup(hasSearcher: false)

        let reply = try await setup.run(Self.idsQuery)

        #expect(reply.codes == ["MISSING_SEARCHER"])
        #expect(reply.messages == [SessionsToolText.noSearcher])
    }

    // MARK: - The aliases

    @Test("the aliases text, limit, items and endCursor reach the names of the schema")
    func theAliasesReachTheSchema() async throws {
        let setup = Setup()

        let reply = try await GraphQLReply.run(Self.aliasQuery, on: setup.graph)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(try await setup.onlyRequest().limit == Self.firstLimit)
        #expect(reply.rewrote("text", to: "query"))
        #expect(reply.rewrote("items", to: "results"))
    }

    // MARK: - The schema

    @Test(
        "the SDL has the searchSessions field and its types",
        arguments: [
            "searchSessions(", "type SessionSearchConnection", "type SessionSearchResult", "type SessionSearchHit",
            "type TextRange", "enum SessionSearchHitKind",
        ])
    func theSchemaHasTheSearchTypes(part: String) {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        #expect(graph.schema.contains(part))
    }
}
