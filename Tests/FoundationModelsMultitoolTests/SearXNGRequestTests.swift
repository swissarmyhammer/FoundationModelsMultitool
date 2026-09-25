import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the query fields of the SearXNG request.
///
/// `KeyedProviderTests` checks what SearXNG shares with the keyed providers.
/// This suite checks the documented query items, the search path under a base
/// URL, and that the request sends no key. Each test calls `request`
/// directly, thus no test uses the network.
@Suite("SearXNGRequests")
struct SearXNGRequestTests {
    /// The text of each query.
    private static let text = "swift programming language"

    /// The site of the site test.
    private static let site = "swift.org"

    /// A count that the query sets.
    private static let count = 7

    /// A base URL with a path, as a host that serves SearXNG under a folder
    /// gives it.
    private static let baseWithPath = "https://host.example/searx/"

    /// The request of a query to the SearXNG instance of the suite.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - key: The key value that the chain gives, or `nil`.
    /// - Returns: The request.
    /// - Throws: When the adapter cannot make the request.
    private static func request(_ query: SearchQuery, key: String? = nil) throws -> URLRequest {
        try KeyedProviderCase.searxng.adapter.request(for: query, key: key)
    }

    @Test("a SearXNG request sends q, then format=json, when the query sets no other field")
    func defaultQuery() throws {
        let request = try Self.request(SearchQuery(text: Self.text))
        #expect(request.url?.query == "q=swift%20programming%20language&format=json")
    }

    @Test(
        "a SearXNG freshness is the documented time_range value",
        arguments: [(SearchFreshness.day, "day"), (.week, "week"), (.month, "month"), (.year, "year")])
    func timeRange(freshness: SearchFreshness, value: String) throws {
        let request = try Self.request(SearchQuery(text: Self.text, freshness: freshness))
        let items = try ProviderRequestReading.queryItems(of: request)
        #expect(items == ["q": Self.text, "format": "json", "time_range": value])
    }

    @Test("a SearXNG request sends the site as a site: term and sends no count field")
    func siteTermAndNoCount() throws {
        let request = try Self.request(SearchQuery(text: Self.text, count: Self.count, site: Self.site))
        let items = try ProviderRequestReading.queryItems(of: request)
        #expect(items == ["q": "\(Self.text) site:\(Self.site)", "format": "json"])
    }

    @Test("a SearXNG request goes to the search path under the path of the base URL")
    func searchPathUnderBasePath() throws {
        let adapter = try SearXNGProvider(base: #require(URL(string: Self.baseWithPath)))
        let url = try #require(adapter.request(for: SearchQuery(text: Self.text), key: nil).url)
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.query = nil
        #expect(components.string == Self.baseWithPath + "search")
    }

    @Test("a SearXNG request sends no key, even when the chain gives one")
    func sendsNoKey() throws {
        let key = KeyedProviderCase.fakeKey
        let request = try Self.request(SearchQuery(text: Self.text), key: key)
        #expect(request.url?.absoluteString.contains(key) == false)
        #expect(request.httpBody == nil)
        #expect(!(request.allHTTPHeaderFields ?? [:]).values.contains { $0.contains(key) })
    }
}
