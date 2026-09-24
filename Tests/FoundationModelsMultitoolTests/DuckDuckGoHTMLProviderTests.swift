import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `DuckDuckGoHTMLProvider`: the request, the parse of the recorded
/// pages, the decode of `uddg` links, duplicates, the count limit, and the
/// challenge page.
///
/// Each test calls `request` or `parse` directly with fixture bytes, thus no
/// test uses the network.
@Suite("DuckDuckGoHTMLProvider")
struct DuckDuckGoHTMLProviderTests {
    /// The resource folder of the recorded pages.
    private static let goldensFolder = "WebGoldens"

    /// The extension of a recorded page.
    private static let htmlExtension = "html"

    /// The recorded results page of the query `buy running shoes`.
    private static let resultsPage = "duckduckgo-results"

    /// The recorded results page of the query `swift programming language`,
    /// with the `df=d` field.
    private static let pastDayPage = "duckduckgo-results-past-day"

    /// The hand-written challenge page.
    private static let challengePage = "duckduckgo-challenge"

    /// The number of organic results in ``resultsPage``.
    private static let recordedOrganicCount = 10

    /// The number of organic results in ``pastDayPage``.
    private static let pastDayOrganicCount = 11

    /// The least number of hits that the recorded page must give.
    private static let minimumRecordedHits = 5

    /// The limit in the limit test. It is less than each page size.
    private static let limitedCount = 3

    /// The form content type of the request.
    private static let formContentType = "application/x-www-form-urlencoded"

    /// The provider under test.
    private static let provider = DuckDuckGoHTMLProvider()

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
        let url = try #require(URL(string: DuckDuckGoHTMLProvider.endpoint))
        let response = try #require(
            HTTPURLResponse(
                url: url, statusCode: WebStub.okStatus, httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=UTF-8"]))
        return try provider.parse(data, response: response, limit: limit)
    }

    /// A hand-written results page that holds `results` in a `.results`
    /// container.
    ///
    /// - Parameter results: The HTML of each result container.
    /// - Returns: The UTF-8 bytes of the page.
    private static func page(_ results: [String]) -> Data {
        Data("<html><body><div class=\"results\">\(results.joined())</div></body></html>".utf8)
    }

    /// The HTML of one organic result container.
    ///
    /// - Parameters:
    ///   - title: The text of the title link.
    ///   - href: The `href` of the title link, or `nil` for a result with no
    ///     title link.
    ///   - snippet: The text of the snippet.
    /// - Returns: The HTML.
    private static func result(title: String, href: String?, snippet: String = "A snippet.") -> String {
        let link = href.map { "<a class=\"result__a\" href=\"\($0)\">\(title)</a>" } ?? "<span>\(title)</span>"
        return "<div class=\"result web-result\"><h2 class=\"result__title\">\(link)</h2>"
            + "<a class=\"result__snippet\">\(snippet)</a></div>"
    }

    /// The fields of the form body of a request, decoded.
    ///
    /// - Parameter request: The request.
    /// - Returns: The value of each field, by name.
    /// - Throws: When the request has no UTF-8 body.
    private static func formFields(of request: URLRequest) throws -> [String: String] {
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let pairs = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        return try Dictionary(
            uniqueKeysWithValues: pairs.map { pair in
                let name = try #require(pair.first)
                let value = try #require(pair.last?.removingPercentEncoding)
                return (name, value)
            })
    }

    // MARK: - The request

    @Test("the request is a form POST of the query to the HTML endpoint")
    func requestIsFormPost() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift concurrency"), key: nil)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://html.duckduckgo.com/html/")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == Self.formContentType)
        #expect(request.httpBody == Data("q=swift%20concurrency".utf8))
    }

    @Test("the form body encodes each reserved character of the query")
    func requestEncodesReservedCharacters() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "c++ & go=fast"), key: nil)
        #expect(request.httpBody == Data("q=c%2B%2B%20%26%20go%3Dfast".utf8))
    }

    @Test("a site adds a site: term to the query")
    func siteAddsTerm() throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift", site: "swift.org"), key: nil)
        #expect(try Self.formFields(of: request) == ["q": "swift site:swift.org"])
    }

    @Test(
        "a freshness is the df field of the form",
        arguments: [(SearchFreshness.day, "d"), (.week, "w"), (.month, "m"), (.year, "y")])
    func freshnessIsDateField(freshness: SearchFreshness, field: String) throws {
        let request = try Self.provider.request(for: SearchQuery(text: "swift", freshness: freshness), key: nil)
        #expect(try Self.formFields(of: request) == ["q": "swift", "df": field])
    }

    @Test("the provider is duckDuckGoHTML and supports freshness, site, and count")
    func nameAndSupports() {
        #expect(Self.provider.name == WebSearchProvider.duckDuckGoHTML.name)
        #expect(Self.provider.supports == [.freshness, .site, .count])
    }

    // MARK: - The recorded pages

    @Test("the recorded page gives its organic hits, each with a direct https URL")
    func recordedPageGivesHttpsHits() throws {
        let hits = try Self.parse(Self.recorded(Self.resultsPage))
        #expect(hits.count >= Self.minimumRecordedHits)
        #expect(hits.count == Self.recordedOrganicCount)
        #expect(hits.map(\.rank) == Array(1...Self.recordedOrganicCount))
        #expect(hits.allSatisfy { $0.url.hasPrefix("https://") })
        #expect(!hits.contains { $0.url.contains("duckduckgo.com") })
    }

    @Test("the recorded page gives the title, the URL, and the snippet, with entities decoded")
    func recordedPageGivesFirstHit() throws {
        let first = try #require(try Self.parse(Self.recorded(Self.resultsPage)).first)
        let expected = WebHit(
            rank: 1,
            title: "Shop Running Shoes | Free Curbside Pickup at DICK'S",
            url: "https://www.dickssportinggoods.com/f/shop-running-shoes",
            snippet: "Shop running shoes from DICK'S Sporting Goods. Browse all running shoes for men, women and "
                + "kids' from Brooks, Nike, adidas, ASICS, HOKA, New Balance and more. Get low prices on running "
                + "shoes with our Best Price Guarantee.")
        #expect(first == expected)
    }

    @Test("the ad results of the recorded page are not in the output")
    func adResultsAreSkipped() throws {
        let titles = try Self.parse(Self.recorded(Self.resultsPage)).map(\.title)
        #expect(!titles.contains { $0.contains("ASICS®") || $0.contains("Nike®") })
    }

    @Test("the recorded past-day page gives its organic hits")
    func pastDayPageGivesHits() throws {
        let hits = try Self.parse(Self.recorded(Self.pastDayPage))
        #expect(hits.count == Self.pastDayOrganicCount)
        #expect(hits.first?.url == "https://www.swift.org/")
    }

    // MARK: - Links, duplicates, and the limit

    @Test("a uddg redirect link gives the decoded target URL")
    func uddgLinkIsDecoded() throws {
        let href = "//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage%3Fa%3D1%26b%3D2&amp;rut=abc123"
        let hits = try Self.parse(Self.page([Self.result(title: "Example", href: href)]))
        #expect(hits.map(\.url) == ["https://example.com/page?a=1&b=2"])
    }

    @Test("a duplicate URL gives one hit, and the ranks stay in order")
    func duplicatesAreRemoved() throws {
        let hits = try Self.parse(
            Self.page([
                Self.result(title: "One", href: "https://one.example/"),
                Self.result(title: "One again", href: "https://one.example/"),
                Self.result(title: "Two", href: "https://two.example/")
            ]))
        #expect(hits.map(\.url) == ["https://one.example/", "https://two.example/"])
        #expect(hits.map(\.rank) == [1, 2])
    }

    @Test("a result with no title link is skipped")
    func resultWithNoLinkIsSkipped() throws {
        let hits = try Self.parse(
            Self.page([
                Self.result(title: "No link", href: nil),
                Self.result(title: "Linked", href: "https://linked.example/")
            ]))
        #expect(hits.map(\.title) == ["Linked"])
    }

    @Test("the parse stops at the limit")
    func parseStopsAtLimit() throws {
        let hits = try Self.parse(Self.recorded(Self.resultsPage), limit: Self.limitedCount)
        #expect(hits.map(\.rank) == Array(1...Self.limitedCount))
    }

    // MARK: - No results

    @Test("the challenge page gives .challenge")
    func challengePageIsChallenge() throws {
        let data = try Self.recorded(Self.challengePage)
        #expect(throws: ProviderFailure.challenge) { try Self.parse(data) }
    }

    @Test("a page with no results and no challenge gives .noResults")
    func emptyPageIsNoResults() {
        #expect(throws: ProviderFailure.noResults) { try Self.parse(Self.page([])) }
    }
}
