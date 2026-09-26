import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the query fields of each keyed provider request, and for the
/// response forms that only one provider has.
///
/// `KeyedProviderTests` checks what each keyed provider shares. This suite
/// checks the documented field names and values of each provider. Each test
/// calls `request` or `parse` directly, thus no test uses the network.
@Suite("KeyedProviderRequests")
struct KeyedProviderRequestTests {
    /// The text of each query.
    private static let text = "swift programming language"

    /// The site of the site tests.
    private static let site = "swift.org"

    /// A count that each provider accepts as it is.
    private static let smallCount = 7

    /// A count above the documented maximum of each provider.
    private static let hugeCount = 500

    /// The documented maximum count of Brave and Tavily.
    private static let braveAndTavilyMaximum = 20

    /// The status of the Brave answer to a token that is not valid.
    private static let braveInvalidTokenStatus = 422

    /// The documented maximum count of Exa.
    private static let exaMaximum = 100

    /// The fixed time of the Exa freshness tests: 2026-09-24T12:00:00Z.
    private static let fixedNow = Date(timeIntervalSince1970: 1_790_251_200)

    /// Makes the request of a query with the fake key.
    ///
    /// - Parameters:
    ///   - adapter: The adapter under test.
    ///   - query: The query.
    /// - Returns: The request.
    /// - Throws: When the adapter cannot make the request.
    private static func request(_ adapter: any SearchProviderAdapter, _ query: SearchQuery) throws -> URLRequest {
        try adapter.request(for: query, key: KeyedProviderCase.fakeKey)
    }

    /// The query items of a Brave request, by name.
    ///
    /// - Parameter query: The query.
    /// - Returns: The value of each query item.
    /// - Throws: When the request has no URL.
    private static func braveItems(_ query: SearchQuery) throws -> [String: String] {
        try ProviderRequestReading.queryItems(of: request(BraveAPIProvider(), query))
    }

    /// The JSON body of a request, decoded.
    ///
    /// - Parameters:
    ///   - type: The type of the body.
    ///   - adapter: The adapter under test.
    ///   - query: The query.
    /// - Returns: The body.
    /// - Throws: When the request has no body, or the body does not decode.
    private static func body<Body: Decodable>(
        _ type: Body.Type, of adapter: any SearchProviderAdapter, _ query: SearchQuery
    ) throws -> Body {
        try ProviderRequestReading.jsonBody(type, of: request(adapter, query))
    }

    // MARK: - Brave

    @Test("a Brave request sends only q when the query sets no other field")
    func braveDefaultQuery() throws {
        #expect(try Self.braveItems(SearchQuery(text: Self.text)) == ["q": Self.text])
    }

    @Test("a Brave request sends the site as a site: term, and the count")
    func braveSiteAndCount() throws {
        let items = try Self.braveItems(SearchQuery(text: Self.text, count: Self.smallCount, site: Self.site))
        #expect(items == ["q": "\(Self.text) site:\(Self.site)", "count": "\(Self.smallCount)"])
    }

    @Test("a Brave request keeps the count at the documented maximum")
    func braveCountMaximum() throws {
        let items = try Self.braveItems(SearchQuery(text: Self.text, count: Self.hugeCount))
        #expect(items["count"] == "\(Self.braveAndTavilyMaximum)")
    }

    @Test(
        "a Brave freshness is the documented freshness value",
        arguments: [(SearchFreshness.day, "pd"), (.week, "pw"), (.month, "pm"), (.year, "py")])
    func braveFreshness(freshness: SearchFreshness, value: String) throws {
        let items = try Self.braveItems(SearchQuery(text: Self.text, freshness: freshness))
        #expect(items == ["q": Self.text, "freshness": value])
    }

    @Test("a Brave request percent-encodes a reserved character of the query")
    func braveEncodesReservedCharacters() throws {
        let request = try Self.request(BraveAPIProvider(), SearchQuery(text: "c++ & go"))
        #expect(request.url?.query == "q=c%2B%2B%20%26%20go")
    }

    @Test("a Brave response with no web object gives .noResults")
    func braveNoWebObject() throws {
        let body = Data("{\"type\": \"search\", \"query\": {\"original\": \"x\"}}".utf8)
        #expect(throws: ProviderFailure.noResults) { try KeyedProviderCase.braveAPI.parse(body) }
    }

    @Test("a Brave answer of HTTP 422 with SUBSCRIPTION_TOKEN_INVALID gives .badKey with the status")
    func braveInvalidTokenIsBadKey() {
        let body = Data("{\"error\": {\"code\": \"SUBSCRIPTION_TOKEN_INVALID\", \"status\": 422}}".utf8)
        #expect(throws: ProviderFailure.badKey(Self.braveInvalidTokenStatus)) {
            try KeyedProviderCase.braveAPI.parse(body, status: Self.braveInvalidTokenStatus)
        }
    }

    @Test("a Brave result with a null description gives an empty snippet")
    func braveNullDescription() throws {
        let hits = try KeyedProviderCase.braveAPI.parse(KeyedProviderCase.braveAPI.recordedResponse())
        #expect(hits.last?.url == "https://github.com/swiftlang/swift")
        #expect(hits.last?.snippet == "")
    }

    // MARK: - Tavily

    @Test("a Tavily request sends only the query when the query sets no other field")
    func tavilyDefaultBody() throws {
        let body = try Self.body(TavilyBody.self, of: TavilyProvider(), SearchQuery(text: Self.text))
        #expect(body == TavilyBody(query: Self.text))
    }

    @Test("a Tavily request sends the count, the time range, and the site")
    func tavilyFullBody() throws {
        let query = SearchQuery(text: Self.text, count: Self.smallCount, freshness: .week, site: Self.site)
        let body = try Self.body(TavilyBody.self, of: TavilyProvider(), query)
        let expected = TavilyBody(
            query: Self.text, maxResults: Self.smallCount, timeRange: "week", includeDomains: [Self.site])
        #expect(body == expected)
    }

    @Test("a Tavily request keeps the count at the documented maximum")
    func tavilyCountMaximum() throws {
        let query = SearchQuery(text: Self.text, count: Self.hugeCount)
        let body = try Self.body(TavilyBody.self, of: TavilyProvider(), query)
        #expect(body.maxResults == Self.braveAndTavilyMaximum)
    }

    @Test(
        "a Tavily freshness is the documented time range",
        arguments: [(SearchFreshness.day, "day"), (.week, "week"), (.month, "month"), (.year, "year")])
    func tavilyTimeRange(freshness: SearchFreshness, value: String) throws {
        let query = SearchQuery(text: Self.text, freshness: freshness)
        #expect(try Self.body(TavilyBody.self, of: TavilyProvider(), query).timeRange == value)
    }

    // MARK: - Exa

    @Test("an Exa request asks for highlights and sends only the query when the query sets no other field")
    func exaDefaultBody() throws {
        let body = try Self.body(ExaBody.self, of: ExaProvider(), SearchQuery(text: Self.text))
        #expect(body == ExaBody(query: Self.text))
    }

    @Test("an Exa request sends the count and the site")
    func exaCountAndSite() throws {
        let query = SearchQuery(text: Self.text, count: Self.smallCount, site: Self.site)
        let body = try Self.body(ExaBody.self, of: ExaProvider(), query)
        #expect(body == ExaBody(query: Self.text, numResults: Self.smallCount, includeDomains: [Self.site]))
    }

    @Test("an Exa request keeps the count at the documented maximum")
    func exaCountMaximum() throws {
        let body = try Self.body(ExaBody.self, of: ExaProvider(), SearchQuery(text: Self.text, count: Self.hugeCount))
        #expect(body.numResults == Self.exaMaximum)
    }

    @Test(
        "an Exa freshness is the start published date before the time of the request",
        arguments: [
            (SearchFreshness.day, "2026-09-23T12:00:00.000Z"), (.week, "2026-09-17T12:00:00.000Z"),
            (.month, "2026-08-24T12:00:00.000Z"), (.year, "2025-09-24T12:00:00.000Z")
        ])
    func exaStartPublishedDate(freshness: SearchFreshness, date: String) throws {
        let adapter = ExaProvider(now: { Self.fixedNow })
        let body = try Self.body(ExaBody.self, of: adapter, SearchQuery(text: Self.text, freshness: freshness))
        #expect(body.startPublishedDate == date)
    }

    @Test("an Exa result with no highlights gives an empty snippet")
    func exaNoHighlights() throws {
        let hits = try KeyedProviderCase.exa.parse(KeyedProviderCase.exa.recordedResponse())
        #expect(hits.last?.url == "https://developer.apple.com/swift/")
        #expect(hits.last?.snippet == "")
    }
}

/// The documented JSON body of a Tavily request.
private struct TavilyBody: Decodable, Equatable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
        case timeRange = "time_range"
        case includeDomains = "include_domains"
    }

    /// The text of the query.
    var query: String

    /// The maximum number of results, or `nil` when the body has none.
    var maxResults: Int?

    /// The time range, or `nil` when the body has none.
    var timeRange: String?

    /// The domains of the results, or `nil` when the body has none.
    var includeDomains: [String]?
}

/// The documented JSON body of an Exa request.
private struct ExaBody: Decodable, Equatable {
    /// The `contents` object of an Exa request.
    struct Contents: Decodable, Equatable {
        /// `true` when the response must hold highlights.
        var highlights: Bool
    }

    /// The text of the query.
    var query: String

    /// The number of results, or `nil` when the body has none.
    var numResults: Int?

    /// The domains of the results, or `nil` when the body has none.
    var includeDomains: [String]?

    /// The earliest published date, or `nil` when the body has none.
    var startPublishedDate: String?

    /// The contents that the response must hold.
    var contents = Contents(highlights: true)
}
