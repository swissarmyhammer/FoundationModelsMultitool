import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the relaxed second run of `WebSearchChain`: the function that
/// makes the relaxed text, and a chain over the real DuckDuckGo adapter whose
/// exact query gets a page with no results.
///
/// The page with no results, `WebGoldens/duckduckgo-no-results.html`, is not a
/// recording. On 2026-10-05 the real service answered two POST requests with
/// ``WebFetchPolicy/packageUserAgent`` and ``exactText`` with HTTP 202 and its
/// anomaly form (a challenge page), not with a page with no results. Thus the
/// page is made from the recorded `duckduckgo-results.html`: the head and the
/// search form stay (the title and the `q` value hold ``exactText``), each
/// result container and the "Next" form are removed, and the
/// `#links.results` container is empty. The page holds 0 `.result__a`.
///
/// A `WebStub` answers each request, thus no test uses the network.
@Suite("RelaxedQuery")
struct RelaxedQueryTests {
    /// The resource folder of the recorded pages.
    private static let goldensFolder = "WebGoldens"

    /// The extension of a recorded page.
    private static let htmlExtension = "html"

    /// The page with no results, made from ``resultsPage``.
    private static let noResultsPage = "duckduckgo-no-results"

    /// The recorded results page of the query `buy running shoes`.
    private static let resultsPage = "duckduckgo-results"

    /// The number of organic results in ``resultsPage``.
    private static let recordedOrganicCount = 10

    /// The exact query of the SWE-bench run that got no results.
    private static let exactText = "Django ticket \"Add model class to app_list context\" Raffaele Salmaso"

    /// The relaxed text of ``exactText``.
    private static let relaxedText = "Django ticket Add model class to app_list context Raffaele Salmaso"

    /// The URL that the stub gives ``noResultsPage`` at.
    private static let exactEndpoint = "https://exact.example/html/"

    /// The URL that the stub gives ``resultsPage`` at.
    private static let relaxedEndpoint = "https://relaxed.example/html/"

    // MARK: - Helpers

    /// A `200` reply whose body is one recorded page.
    ///
    /// - Parameter name: The name of the page, with no extension.
    /// - Returns: The reply.
    /// - Throws: When the test bundle does not hold the page.
    private static func pageReply(_ name: String) throws -> WebStubReply {
        let text = try TestResource.bundledText(named: name, withExtension: htmlExtension, in: goldensFolder)
        return .respond(
            status: WebStub.okStatus, headers: ["Content-Type": "text/html; charset=UTF-8"], body: Data(text.utf8))
    }

    /// The URL of a URL text.
    ///
    /// - Parameter text: The absolute URL text.
    /// - Returns: The URL.
    /// - Throws: When `text` is not a URL.
    private static func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    // MARK: - The relaxed text

    @Test("the relaxed text has no straight quote marks")
    func straightQuotesAreRemoved() {
        #expect(WebSearchChain.relaxedText(of: Self.exactText) == Self.relaxedText)
    }

    @Test(
        "the relaxed text has no typographic quote marks",
        arguments: ["\u{201C}app list\u{201D} model", "\u{201E}app list\u{201C} model", "\u{201F}app list\u{201D} model"])
    func typographicQuotesAreRemoved(text: String) {
        #expect(WebSearchChain.relaxedText(of: text) == "app list model")
    }

    @Test(
        "each search operator is removed, and its value stays",
        arguments: [
            ("swift site:swift.org", "swift swift.org"),
            ("swift intitle:concurrency", "swift concurrency"),
            ("swift inurl:docs", "swift docs"),
            ("swift filetype:pdf", "swift pdf")
        ])
    func operatorIsRemoved(text: String, relaxed: String) {
        #expect(WebSearchChain.relaxedText(of: text) == relaxed)
    }

    @Test("a search operator in upper case is removed")
    func upperCaseOperatorIsRemoved() {
        #expect(WebSearchChain.relaxedText(of: "swift SITE:swift.org InTitle:actors") == "swift swift.org actors")
    }

    @Test("an operator with a quoted value keeps the words of the value")
    func operatorWithQuotedValue() {
        #expect(WebSearchChain.relaxedText(of: "intitle:\"app list\" django") == "app list django")
    }

    @Test("a leading - or + is removed from a word, and a hyphen inside a word stays")
    func leadingSignIsRemoved() {
        #expect(WebSearchChain.relaxedText(of: "swift -objc +async app-list") == "swift objc async app-list")
    }

    @Test("OR and AND as words are removed, and or and and in lower case stay")
    func booleanOperatorsAreRemoved() {
        #expect(WebSearchChain.relaxedText(of: "swift OR rust AND go") == "swift rust go")
        #expect(WebSearchChain.relaxedText(of: "swift or rust and go") == "swift or rust and go")
    }

    @Test("the whitespace collapses to one space between words, with none at the ends")
    func whitespaceCollapses() {
        #expect(WebSearchChain.relaxedText(of: "  swift \t concurrency\n actors  ") == "swift concurrency actors")
    }

    @Test("a text of operators only gives an empty text")
    func operatorsOnlyGiveEmptyText() {
        #expect(WebSearchChain.relaxedText(of: "\"\" site: - + OR") == "")
    }

    @Test("a text with no quote marks and no operators stays the same")
    func plainTextStaysTheSame() {
        #expect(WebSearchChain.relaxedText(of: "swift concurrency") == "swift concurrency")
    }

    // MARK: - The chain

    @Test("an exact query with no results runs again with the relaxed text, and the note comes first")
    func noResultsRunsAgainRelaxed() async throws {
        let adapter = try QueryRoutedAdapter(
            wrapping: DuckDuckGoHTMLProvider(),
            routes: [Self.exactText: Self.url(Self.exactEndpoint), Self.relaxedText: Self.url(Self.relaxedEndpoint)])
        let stub = try WebStub(routes: [
            Self.exactEndpoint: Self.pageReply(Self.noResultsPage),
            Self.relaxedEndpoint: Self.pageReply(Self.resultsPage)
        ])
        let chain = WebSearchChain(providers: [(.duckDuckGoHTML, adapter)], fetcher: stub.makeFetcher(), environment: [:])
        let outcome = await chain.search(SearchQuery(text: Self.exactText))
        let hits = try #require(outcome.hitList)
        #expect(hits.count == Self.recordedOrganicCount)
        #expect(
            outcome
                == .hits(
                    provider: "duckDuckGoHTML", hits: hits,
                    notes: ["No results for the exact query; these are the results for: \(Self.relaxedText)"]))
        #expect(stub.requestedURLs == [Self.exactEndpoint, Self.relaxedEndpoint])
    }
}
