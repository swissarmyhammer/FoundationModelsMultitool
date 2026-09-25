import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the query fields of the Serper and Kagi requests, and for the
/// response forms that only one of the two providers has.
///
/// `KeyedProviderTests` checks what each keyed provider shares. This suite
/// checks the documented field names and values. Each test calls `request` or
/// `parse` directly, thus no test uses the network.
@Suite("SerperKagiRequests")
struct SerperKagiRequestTests {
    /// The text of each query.
    private static let text = "swift programming language"

    /// The site of the site tests.
    private static let site = "swift.org"

    /// A count that each provider accepts as it is.
    private static let smallCount = 7

    /// A count above the documented maximum of each provider.
    private static let hugeCount = 5000

    /// The documented maximum count of Serper.
    private static let serperMaximum = 100

    /// The documented maximum count of Kagi.
    private static let kagiMaximum = 1024

    /// The fixed time of the Kagi freshness tests: 2026-09-24T12:00:00Z.
    private static let fixedNow = Date(timeIntervalSince1970: 1_790_251_200)

    /// The JSON body of the request of a query, decoded.
    ///
    /// - Parameters:
    ///   - type: The type of the body.
    ///   - adapter: The adapter under test.
    ///   - query: The query.
    /// - Returns: The body.
    /// - Throws: When the request cannot be made, or the body does not decode.
    private static func body<Body: Decodable>(
        _ type: Body.Type, of adapter: any SearchProviderAdapter, _ query: SearchQuery
    ) throws -> Body {
        try ProviderRequestReading.jsonBody(type, of: adapter.request(for: query, key: KeyedProviderCase.fakeKey))
    }

    // MARK: - Serper

    @Test("a Serper request sends only q when the query sets no other field")
    func serperDefaultBody() throws {
        let body = try Self.body(SerperBody.self, of: SerperProvider(), SearchQuery(text: Self.text))
        #expect(body == SerperBody(query: Self.text))
    }

    @Test("a Serper request sends the site as a site: term, the count as num, and the age limit as tbs")
    func serperFullBody() throws {
        let query = SearchQuery(text: Self.text, count: Self.smallCount, freshness: .week, site: Self.site)
        let body = try Self.body(SerperBody.self, of: SerperProvider(), query)
        #expect(body == SerperBody(query: "\(Self.text) site:\(Self.site)", num: Self.smallCount, tbs: "qdr:w"))
    }

    @Test("a Serper request keeps the count at the documented maximum")
    func serperCountMaximum() throws {
        let query = SearchQuery(text: Self.text, count: Self.hugeCount)
        #expect(try Self.body(SerperBody.self, of: SerperProvider(), query).num == Self.serperMaximum)
    }

    @Test(
        "a Serper freshness is the documented tbs value",
        arguments: [(SearchFreshness.day, "qdr:d"), (.week, "qdr:w"), (.month, "qdr:m"), (.year, "qdr:y")])
    func serperTimeFilter(freshness: SearchFreshness, value: String) throws {
        let query = SearchQuery(text: Self.text, freshness: freshness)
        #expect(try Self.body(SerperBody.self, of: SerperProvider(), query).tbs == value)
    }

    @Test("a Serper result with no snippet gives an empty snippet")
    func serperNoSnippet() throws {
        let hits = try KeyedProviderCase.serper.parse(KeyedProviderCase.serper.recordedResponse())
        #expect(hits.last?.url == "https://github.com/swiftlang/swift")
        #expect(hits.last?.snippet == "")
    }

    @Test("a Serper response with no organic results gives .noResults")
    func serperNoOrganicResults() {
        let body = Data("{\"searchParameters\": {\"q\": \"x\"}, \"relatedSearches\": [{\"query\": \"y\"}]}".utf8)
        #expect(throws: ProviderFailure.noResults) { try KeyedProviderCase.serper.parse(body) }
    }

    // MARK: - Kagi

    @Test("a Kagi request sends only the query when the query sets no other field")
    func kagiDefaultBody() throws {
        let body = try Self.body(KagiBody.self, of: KagiProvider(), SearchQuery(text: Self.text))
        #expect(body == KagiBody(query: Self.text))
    }

    @Test("a Kagi request sends the count as limit, and the site in the lens")
    func kagiCountAndSite() throws {
        let query = SearchQuery(text: Self.text, count: Self.smallCount, site: Self.site)
        let body = try Self.body(KagiBody.self, of: KagiProvider(), query)
        let expected = KagiBody(
            query: Self.text, limit: Self.smallCount, lens: KagiLensBody(sitesIncluded: [Self.site]))
        #expect(body == expected)
    }

    @Test("a Kagi request keeps the count at the documented maximum")
    func kagiCountMaximum() throws {
        let query = SearchQuery(text: Self.text, count: Self.hugeCount)
        #expect(try Self.body(KagiBody.self, of: KagiProvider(), query).limit == Self.kagiMaximum)
    }

    @Test(
        "a Kagi freshness is the filter date before the day of the request",
        arguments: [
            (SearchFreshness.day, "2026-09-23"), (.week, "2026-09-17"), (.month, "2026-08-24"), (.year, "2025-09-24")
        ])
    func kagiAfterDate(freshness: SearchFreshness, date: String) throws {
        let adapter = KagiProvider(now: { Self.fixedNow })
        let body = try Self.body(KagiBody.self, of: adapter, SearchQuery(text: Self.text, freshness: freshness))
        #expect(body.filters == KagiBody.Filters(after: date))
    }

    @Test("the Kagi related searches of the recorded response are not hits")
    func kagiRelatedSearchesAreNotHits() throws {
        let hits = try KeyedProviderCase.kagi.parse(KeyedProviderCase.kagi.recordedResponse())
        #expect(!hits.contains { $0.url.hasPrefix("https://kagi.com/search") })
    }

    @Test("a Kagi response with only related searches gives .noResults")
    func kagiOnlyRelatedSearches() {
        let related = "{\"url\": \"https://kagi.com/search?q=swift\", \"title\": \"swift\"}"
        let body = Data("{\"meta\": {\"trace\": \"t\"}, \"data\": {\"related_search\": [\(related)]}}".utf8)
        #expect(throws: ProviderFailure.noResults) { try KeyedProviderCase.kagi.parse(body) }
    }

    @Test("a Kagi title with an HTML entity gives the decoded text")
    func kagiDecodesEntities() throws {
        let hits = try KeyedProviderCase.kagi.parse(KeyedProviderCase.kagi.recordedResponse())
        let apple = try #require(hits.first { $0.url == "https://developer.apple.com/swift/" })
        #expect(apple.title == "Swift - Apple Developer & Documentation")
    }

    @Test("a Kagi result with no snippet gives an empty snippet")
    func kagiNoSnippet() throws {
        let hits = try KeyedProviderCase.kagi.parse(KeyedProviderCase.kagi.recordedResponse())
        #expect(hits.last?.url == "https://github.com/swiftlang/swift")
        #expect(hits.last?.snippet == "")
    }
}

/// The documented JSON body of a Serper search request.
private struct SerperBody: Decodable, Equatable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case query = "q"
        case num
        case tbs
    }

    /// The text of the query.
    var query: String

    /// The number of results, or `nil` when the body has none.
    var num: Int?

    /// The time filter, or `nil` when the body has none.
    var tbs: String?
}

/// The documented JSON body of a Kagi search request.
private struct KagiBody: Decodable, Equatable {
    /// The `filters` object of a Kagi request.
    struct Filters: Decodable, Equatable {
        /// The earliest date of the results, or `nil` when the body has none.
        var after: String?
    }

    /// The text of the query.
    var query: String

    /// The maximum number of results, or `nil` when the body has none.
    var limit: Int?

    /// The filters, or `nil` when the body has none.
    var filters: Filters?

    /// The lens, or `nil` when the body has none.
    var lens: KagiLensBody?
}

/// The documented `lens` object of a Kagi search request.
private struct KagiLensBody: Decodable, Equatable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case sitesIncluded = "sites_included"
    }

    /// The domains of the results, or `nil` when the lens has none.
    var sitesIncluded: [String]?
}
