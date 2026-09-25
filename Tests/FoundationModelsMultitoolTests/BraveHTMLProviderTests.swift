import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `BraveHTMLProvider`: the request, the parse of the recorded
/// pages, the ported fixtures of `brave.rs`, and the challenge page.
///
/// Each test calls `request` or `parse` directly with fixture bytes, or runs
/// a chain whose `WebStub` answers each request. Thus no test uses the
/// network.
@Suite("BraveHTMLProvider")
struct BraveHTMLProviderTests {
    /// The resource folder of the recorded pages.
    private static let goldensFolder = "WebGoldens"

    /// The extension of a recorded page.
    private static let htmlExtension = "html"

    /// The recorded results page of the query `swift programming language`.
    private static let resultsPage = "brave-results"

    /// The recorded results page of the same query, with `tf=pd`.
    private static let pastDayPage = "brave-results-past-day"

    /// The hand-written challenge page.
    private static let challengePage = "brave-challenge"

    /// The number of `[data-pos]` containers in ``resultsPage``. Each one has
    /// a title and a different `https` URL.
    private static let recordedResultCount = 21

    /// The number of `[data-pos]` containers in ``pastDayPage``.
    private static let pastDayResultCount = 2

    /// The least number of hits that the recorded page must give.
    private static let minimumRecordedHits = 5

    /// The rank of the hit in ``resultsPage`` whose title has an entity.
    private static let entityHitRank = 13

    /// The limit in the limit test. It is less than each page size.
    private static let limitedCount = 3

    /// The number of containers in the page of the default-count fixture.
    private static let manyResultCount = 15

    /// The count of the default-count fixture: the default of `brave.rs`.
    private static let rustDefaultCount = 10

    /// The status of a rate limit.
    private static let rateLimitStatus = 429

    /// The status of a server that is not available.
    private static let unavailableStatus = 503

    /// The URL of the request of the query `swift`.
    private static let swiftRequestURL = "https://search.brave.com/search?q=swift&source=web"

    /// The endpoint of the fake second provider in the chain tests.
    private static let secondEndpoint = "https://duckduckgohtml.example/search"

    /// The provider under test.
    private static let provider = BraveHTMLProvider()

    // MARK: - Helpers

    /// The bytes of one recorded page.
    ///
    /// - Parameter name: The name of the page, with no extension.
    /// - Returns: The UTF-8 bytes of the page.
    /// - Throws: When the test bundle does not hold the page.
    private static func recorded(_ name: String) throws -> Data {
        try Data(TestResource.bundledText(named: name, withExtension: htmlExtension, in: goldensFolder).utf8)
    }

    /// Reads the hits of a page with the provider under test.
    ///
    /// - Parameters:
    ///   - data: The bytes of the page.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits.
    /// - Throws: The failure of the parse, or an error when the response
    ///   cannot be made.
    private static func parse(_ data: Data, limit: Int? = nil) throws -> [WebHit] {
        let url = try #require(URL(string: swiftRequestURL))
        let response = try #require(
            HTTPURLResponse(
                url: url, statusCode: WebStub.okStatus, httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=utf-8"]))
        return try provider.parse(data, response: response, limit: limit)
    }

    /// Reads the hits of a hand-written page.
    ///
    /// - Parameters:
    ///   - body: The HTML inside `<body>`.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits.
    /// - Throws: The failure of the parse.
    private static func parse(page body: String, limit: Int? = nil) throws -> [WebHit] {
        try parse(Data("<html><body>\(body)</body></html>".utf8), limit: limit)
    }

    /// The HTML of one result container with a `.title` span in its link.
    ///
    /// - Parameters:
    ///   - position: The value of `data-pos`.
    ///   - href: The `href` of the link.
    ///   - title: The text of the `.title` span.
    /// - Returns: The HTML.
    private static func container(_ position: Int, href: String, title: String) -> String {
        "<div data-pos=\"\(position)\"><a href=\"\(href)\"><span class=\"title\">\(title)</span></a></div>"
    }

    /// Runs a search whose first provider is the Brave provider under test,
    /// which gets `reply`, and whose second provider gives one hit.
    ///
    /// - Parameter reply: The reply to the Brave request.
    /// - Returns: The outcome of the search.
    private static func searchAfterBrave(gets reply: WebStubReply) async throws -> SearchOutcome {
        let endpoint = try #require(URL(string: secondEndpoint))
        let second = FakeSearchAdapter(name: "duckDuckGoHTML", endpoint: endpoint)
        let secondReply = WebStubReply.respond(
            status: WebStub.okStatus, headers: ["Content-Type": "text/plain"],
            body: Data("Result 1\thttps://result.example/1".utf8))
        let stub = WebStub(routes: [swiftRequestURL: reply, secondEndpoint: secondReply])
        let chain = WebSearchChain(
            providers: [(.braveHTML, provider), (.duckDuckGoHTML, second)], fetcher: stub.makeFetcher(),
            environment: [:])
        return await chain.search(SearchQuery(text: "swift"))
    }

    /// The outcome of ``searchAfterBrave(gets:)`` when the second provider
    /// wins after the Brave provider fails with `note`.
    ///
    /// - Parameter note: The note of the Brave failure.
    /// - Returns: The outcome.
    private static func secondProviderWins(after note: String) -> SearchOutcome {
        .hits(
            provider: "duckDuckGoHTML",
            hits: [WebHit(rank: 1, title: "Result 1", url: "https://result.example/1", snippet: "")],
            notes: [note])
    }

    // MARK: - The request

    @Test("the request is a GET of the results page with the browser headers")
    func requestIsGet() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift concurrency"), key: nil)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://search.brave.com/search?q=swift%20concurrency&source=web")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/html")
        #expect(
            request.value(forHTTPHeaderField: "User-Agent")
                == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/131.0.0.0 Safari/537.36")
    }

    @Test("the query encodes each reserved character")
    func requestEncodesReservedCharacters() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "c++ & go=fast"), key: nil)
        #expect(request.url?.absoluteString == "https://search.brave.com/search?q=c%2B%2B%20%26%20go%3Dfast&source=web")
    }

    @Test("a site adds a site: term to the query")
    func siteAddsTerm() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift", site: "swift.org"), key: nil)
        #expect(request.url?.absoluteString == "https://search.brave.com/search?q=swift%20site%3Aswift.org&source=web")
    }

    @Test(
        "a freshness is the tf query item",
        arguments: [(SearchFreshness.day, "pd"), (.week, "pw"), (.month, "pm"), (.year, "py")])
    func freshnessIsTimeFilter(freshness: SearchFreshness, value: String) throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift", freshness: freshness), key: nil)
        #expect(request.url?.absoluteString == "https://search.brave.com/search?q=swift&source=web&tf=\(value)")
    }

    @Test("the provider is braveHTML and supports freshness, site, and count")
    func nameAndSupports() {
        #expect(Self.provider.name == WebSearchProvider.braveHTML.name)
        #expect(Self.provider.supports == [.freshness, .site, .count])
    }

    // MARK: - The recorded pages

    @Test("the recorded page gives a hit for each container, each with an https URL and a title")
    func recordedPageGivesHttpsHits() throws {
        let hits = try Self.parse(Self.recorded(Self.resultsPage))
        #expect(hits.count >= Self.minimumRecordedHits)
        #expect(hits.map(\.rank) == Array(1...Self.recordedResultCount))
        #expect(hits.allSatisfy { $0.url.hasPrefix("https://") && !$0.title.isEmpty })
    }

    @Test("the recorded page gives the title and the URL of the first result")
    func recordedPageGivesFirstHit() throws {
        let first = try #require(try Self.parse(Self.recorded(Self.resultsPage)).first)
        #expect(first.title == "Swift Programming Language")
        #expect(first.url == "https://www.swift.org/")
    }

    @Test("the recorded page gives the .generic-snippet .content text of the first result")
    func recordedPageGivesFirstSnippet() throws {
        let first = try #require(try Self.parse(Self.recorded(Self.resultsPage)).first)
        #expect(
            first.snippet
                == "Swift is a general-purpose programming language built using a modern approach to safety, "
                + "performance, and software design patterns.")
    }

    @Test("the recorded page gives a title with its entity decoded")
    func recordedPageDecodesEntity() throws {
        let hits = try Self.parse(Self.recorded(Self.resultsPage))
        let hit = try #require(hits.first { $0.rank == Self.entityHitRank })
        #expect(hit.title == "Swift Courses & Tutorials | Codecademy")
        #expect(hit.url == "https://www.codecademy.com/catalog/language/swift")
    }

    @Test("the .generic-snippet .content text comes before the .snippet-description text")
    func genericSnippetComesFirst() throws {
        let hits = try Self.parse(
            page: """
                <div data-pos="1">
                    <a href="https://example.com"><span class="title">Example</span></a>
                    <p class="snippet-description">The description of the old markup.</p>
                    <div class="generic-snippet"><div class="content">The snippet of the current markup.</div></div>
                </div>
                """)
        #expect(hits.map(\.snippet) == ["The snippet of the current markup."])
    }

    @Test("the recorded past-day page gives its hits")
    func pastDayPageGivesHits() throws {
        let hits = try Self.parse(Self.recorded(Self.pastDayPage))
        #expect(hits.count == Self.pastDayResultCount)
        #expect(hits.first?.url == "https://en.wikipedia.org/wiki/Swift_(programming_language)")
    }

    @Test("the parse stops at the limit")
    func parseStopsAtLimit() throws {
        let hits = try Self.parse(Self.recorded(Self.resultsPage), limit: Self.limitedCount)
        #expect(hits.map(\.rank) == Array(1...Self.limitedCount))
    }
}

// MARK: - The ported fixtures of brave.rs

extension BraveHTMLProviderTests {
    @Test("test_parse_brave_html: the title, the URL, and the snippet of each container")
    func parsesTitleURLAndSnippet() throws {
        let hits = try Self.parse(
            page: """
                <div data-pos="1">
                    <a href="https://www.rust-lang.org/">
                        <span class="title">Rust Programming Language</span>
                    </a>
                    <p class="snippet-description">A systems programming language focused on safety and performance.</p>
                </div>
                <div data-pos="2">
                    <a href="https://doc.rust-lang.org/book/">
                        <span class="title">The Rust Programming Language Book</span>
                    </a>
                    <p class="snippet-description">The official Rust book for learning the language.</p>
                </div>
                """)
        #expect(
            hits == [
                WebHit(
                    rank: 1, title: "Rust Programming Language", url: "https://www.rust-lang.org/",
                    snippet: "A systems programming language focused on safety and performance."),
                WebHit(
                    rank: 2, title: "The Rust Programming Language Book", url: "https://doc.rust-lang.org/book/",
                    snippet: "The official Rust book for learning the language.")
            ])
    }

    @Test("test_parse_no_results: a page with no container gives .noResults")
    func pageWithNoContainerIsNoResults() {
        #expect(throws: ProviderFailure.noResults) { try Self.parse(page: "<div>No results</div>") }
    }

    @Test("test_search_returns_no_results_error_on_empty_html: a page with only text gives .noResults")
    func pageWithOnlyTextIsNoResults() {
        #expect(throws: ProviderFailure.noResults) { try Self.parse(page: "<p>No search results found.</p>") }
    }

    @Test("test_deduplicates_urls: a duplicate URL gives one hit, and the ranks stay in order")
    func duplicatesAreRemoved() throws {
        let hits = try Self.parse(
            page: Self.container(1, href: "https://example.com", title: "First")
                + Self.container(2, href: "https://example.com", title: "Duplicate")
                + Self.container(3, href: "https://other.com", title: "Other"))
        #expect(hits.map(\.title) == ["First", "Other"])
        #expect(hits.map(\.rank) == [1, 2])
    }

    @Test("test_title_fallback_from_anchor_text: with no .title, the title is the link text")
    func titleFallsBackToLinkText() throws {
        let hits = try Self.parse(
            page: "<div data-pos=\"1\"><a href=\"https://example.com/page\">Example Page Title</a></div>")
        #expect(hits.map(\.title) == ["Example Page Title"])
        #expect(hits.map(\.url) == ["https://example.com/page"])
    }

    @Test("test_description_fallback_to_paragraph: the snippet is the first paragraph of more than 20 characters")
    func snippetFallsBackToLongParagraph() throws {
        let hits = try Self.parse(
            page: """
                <div data-pos="1">
                    <a href="https://example.com"><span class="title">Example</span></a>
                    <p>Too short</p>
                    <p>This is a longer paragraph that should be used as the description fallback.</p>
                </div>
                """)
        #expect(hits.map(\.snippet) == ["This is a longer paragraph that should be used as the description fallback."])
    }

    @Test("test_max_results_limiting: the parse stops at the count")
    func parseStopsAtCount() throws {
        let hits = try Self.parse(
            page: Self.container(1, href: "https://first.com", title: "First Result")
                + Self.container(2, href: "https://second.com", title: "Second Result")
                + Self.container(3, href: "https://third.com", title: "Third Result"),
            limit: 1)
        #expect(hits.map(\.title) == ["First Result"])
    }

    @Test("test_search_uses_results_count_from_request: 15 containers and a count of 10 give 10 hits")
    func manyContainersStopAtCount() throws {
        let page = (1...Self.manyResultCount)
            .map { Self.container($0, href: "https://result\($0).com", title: "Result \($0)") }
            .joined()
        #expect(try Self.parse(page: page, limit: Self.rustDefaultCount).count == Self.rustDefaultCount)
    }

    @Test("test_parse_result_elements_without_valid_links_are_skipped: no link and a relative link are skipped")
    func containersWithoutWebLinkAreSkipped() throws {
        let hits = try Self.parse(
            page: "<div data-pos=\"1\"><span>No link here at all</span></div>"
                + Self.container(2, href: "/relative/path", title: "Relative URL")
                + Self.container(3, href: "https://valid.com", title: "Valid Result"))
        #expect(hits.map(\.url) == ["https://valid.com"])
    }

    @Test("test_parse_element_with_no_title_and_no_link_is_skipped: an ftp link is skipped")
    func ftpLinkIsSkipped() throws {
        let hits = try Self.parse(
            page: "<div data-pos=\"1\"><a href=\"ftp://unsupported.com\">FTP link</a></div>"
                + "<div data-pos=\"2\"><a href=\"https://ok.com\">OK Title</a></div>")
        #expect(hits.map(\.title) == ["OK Title"])
    }

    @Test("an entity in the title and the snippet is decoded")
    func entitiesAreDecoded() throws {
        let hits = try Self.parse(
            page: "<div data-pos=\"1\"><a href=\"https://example.com\">"
                + "<span class=\"title\">Q&amp;A &#8211; &quot;Swift&quot;</span></a>"
                + "<p class=\"snippet-description\">Tips &lt;and&gt; tricks</p></div>")
        #expect(hits.map(\.title) == ["Q&A \u{2013} \"Swift\""])
        #expect(hits.map(\.snippet) == ["Tips <and> tricks"])
    }

    // MARK: - The challenge page and the chain

    @Test("the challenge page gives .challenge")
    func challengePageIsChallenge() throws {
        let data = try Self.recorded(Self.challengePage)
        #expect(throws: ProviderFailure.challenge) { try Self.parse(data) }
    }

    @Test(
        "a page with no container and one challenge marker gives .challenge",
        arguments: [
            "<form action=\"/search/CAPTCHA\"><button>Go</button></form>", "<p>Solve the Captcha to go on.</p>"
        ])
    func challengeMarkerIsChallenge(body: String) {
        #expect(throws: ProviderFailure.challenge) { try Self.parse(page: body) }
    }

    @Test("the word captcha in a script is not a challenge marker")
    func scriptTextIsNoMarker() {
        let body = "<p>No results.</p><script>const text = \"Switch to traditional captcha\"</script>"
        #expect(throws: ProviderFailure.noResults) { try Self.parse(page: body) }
    }

    @Test("a challenge page sends the chain to the next provider")
    func challengeGoesToNextProvider() async throws {
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: ["Content-Type": "text/html; charset=utf-8"],
            body: try Self.recorded(Self.challengePage))
        let outcome = try await Self.searchAfterBrave(gets: reply)
        #expect(outcome == Self.secondProviderWins(after: "braveHTML: skipped, blocked by a challenge page."))
    }

    @Test(
        "test_search_http_non_success_status and test_search_http_server_error: the chain goes to the next provider",
        arguments: [
            (rateLimitStatus, "braveHTML: skipped, blocked (HTTP 429)."),
            (unavailableStatus, "braveHTML: skipped, server error (HTTP 503).")
        ])
    func failedStatusGoesToNextProvider(status: Int, note: String) async throws {
        let reply = WebStubReply.respond(status: status, headers: [:], body: Data())
        let outcome = try await Self.searchAfterBrave(gets: reply)
        #expect(outcome == Self.secondProviderWins(after: note))
    }

    @Test("test_search_successful_parse_with_results: the chain gives the hits of the Brave page")
    func braveHitsWin() async throws {
        let page = Self.container(1, href: "https://example.com", title: "Example Result")
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data("<html><body>\(page)</body></html>".utf8))
        let outcome = try await Self.searchAfterBrave(gets: reply)
        let hit = WebHit(rank: 1, title: "Example Result", url: "https://example.com", snippet: "")
        #expect(outcome == .hits(provider: "braveHTML", hits: [hit], notes: []))
    }
}
