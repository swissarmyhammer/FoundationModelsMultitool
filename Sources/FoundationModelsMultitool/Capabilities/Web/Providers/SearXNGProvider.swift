// `SearXNGProvider` — the search provider of a SearXNG instance that the host
// runs (web.md § "The provider list" and § "Security").
//
// The provider sends `GET <base>/search?q=…&format=json` and no key. The base
// URL is host configuration, thus the chain sends the search request with no
// guard check. The guard still checks each redirect hop of that request, and
// each result URL that a snippet fetches. The request has no count field, thus
// the count is the limit of the parse. A site adds a `site:<host>` term to
// `q`. The provider reads `results`, and the snippet of a hit is the `content`
// field of its result. It does not read `answers`, `infoboxes`, or
// `suggestions`.

import Foundation

/// The search provider of a SearXNG instance.
///
/// The documentation of the API: https://docs.searxng.org/dev/search_api.html
/// (the `time_range` values: `searx/webadapter.py` in
/// https://github.com/searxng/searxng)
struct SearXNGProvider: SearchProviderAdapter {
    /// The path of the search endpoint under the base URL.
    private static let searchPath = "search"

    /// The query item of the query text.
    private static let queryItem = "q"

    /// The query item of the response format.
    private static let formatItem = "format"

    /// The value of ``formatItem`` for a JSON response. An instance sends
    /// JSON only when its settings turn the format on.
    private static let jsonFormat = "json"

    /// The query item of the age limit.
    private static let timeRangeItem = "time_range"

    /// The value of ``timeRangeItem`` for each age limit.
    private static let timeRanges = SearchFreshnessValues(
        day: "day", week: "week", month: "month", year: "year")

    /// The name of the provider: the name of the case
    /// `WebSearchProvider.searxng`.
    let name = "searxng"

    /// The query fields that the provider sends: the `time_range` item, a
    /// `site:` term in `q`, and the limit of the parse.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// `true`: the base URL of the instance is host configuration, thus the
    /// guard does not check the search request.
    let isHostConfiguration = true

    /// The base URL of the instance, for example `http://127.0.0.1:8888`.
    private let base: URL

    /// Makes the provider.
    ///
    /// - Parameter base: The base URL of the instance. The search endpoint is
    ///   the `search` path under it.
    init(base: URL) {
        self.base = base
    }

    /// Makes a `GET` request with the query in the URL.
    ///
    /// - Parameters:
    ///   - query: The query. A site adds a `site:<host>` term to the text.
    ///     The count is not sent.
    ///   - key: Not used. SearXNG takes no key.
    /// - Returns: The request.
    /// - Throws: ``InvalidProviderEndpoint`` when the URL cannot be made.
    func request(for query: SearchQuery, key _: String?) throws -> URLRequest {
        let endpoint = base.appending(path: Self.searchPath).absoluteString
        return try SearchProviderSupport.jsonGetRequest(to: endpoint, items: Self.queryItems(of: query))
    }

    /// Reads the hits of a response.
    ///
    /// - Parameters:
    ///   - data: The JSON body of the response.
    ///   - response: The response. Its status comes first.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits, with rank 1 first. The snippet is the `content`
    ///   of the result.
    /// - Throws: The failure of the status, `.noResults` for a response with
    ///   no results, and `.parse` when the body cannot be read.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let body = try SearchProviderSupport.decodedBody(SearXNGResponse.self, from: data, response: response)
        let results = body.results.map { result in
            ProviderResult(title: result.title ?? "", url: result.url ?? "", snippet: result.content ?? "")
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }

    /// The query items of a query, in order.
    ///
    /// - Parameter query: The query.
    /// - Returns: The `q` item and the `format` item, then the `time_range`
    ///   item when the query sets an age limit.
    private static func queryItems(of query: SearchQuery) -> [(name: String, value: String)] {
        let timeRangeItems = query.freshness.map { [(name: timeRangeItem, value: timeRanges.value(for: $0))] } ?? []
        return [(name: queryItem, value: query.textWithSiteTerm), (name: formatItem, value: jsonFormat)]
            + timeRangeItems
    }
}

/// The part of a SearXNG JSON response that the provider reads.
private struct SearXNGResponse: Decodable {
    /// One result.
    struct SearchResult: Decodable {
        /// The URL of the page, or `nil`.
        let url: String?

        /// The title of the page, or `nil`.
        let title: String?

        /// A short text from the page, or `nil`.
        let content: String?
    }

    /// The results, in rank order.
    let results: [SearchResult]
}
