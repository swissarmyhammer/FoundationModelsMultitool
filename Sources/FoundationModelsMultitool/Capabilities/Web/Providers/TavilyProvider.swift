// `TavilyProvider` — the keyed search provider of the Tavily search API
// (web.md § "The provider list").
//
// The provider sends `POST /search` with a JSON body and the key in the
// `Authorization: Bearer <key>` header. It reads `results`, and the snippet
// of a hit is the `content` field of its result.

import Foundation

/// The keyed search provider of the Tavily search API.
///
/// The documentation of the API:
/// https://docs.tavily.com/documentation/api-reference/endpoint/search
struct TavilyProvider: SearchProviderAdapter {
    /// The URL of the search endpoint.
    static let endpoint = "https://api.tavily.com/search"

    /// The header that holds the key.
    static let keyHeader = "Authorization"

    /// The text before the key in ``keyHeader``.
    private static let bearerPrefix = "Bearer "

    /// The counts that the service accepts. The service accepts 0 too, but a
    /// search with no results has no use.
    private static let countRange = 1...20

    /// The value of the `time_range` field for each age limit.
    private static let timeRanges = SearchFreshnessValues(
        day: "day", week: "week", month: "month", year: "year")

    /// The name of the provider: the name of the case
    /// `WebSearchProvider.tavily`.
    let name = "tavily"

    /// The query fields that the provider sends: `time_range`,
    /// `include_domains`, and `max_results`.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// `false`: the endpoint is fixed, thus the guard checks the search
    /// request.
    let isHostConfiguration = false

    /// Makes a `POST` request with the query as a JSON body and the key in
    /// ``keyHeader``.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - key: The key value.
    /// - Returns: The request.
    /// - Throws: ``MissingProviderKey`` when `key` is `nil` or empty,
    ///   ``InvalidProviderEndpoint`` when ``endpoint`` is not a URL, or the
    ///   error of the encoder.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest {
        let key = try SearchProviderSupport.requiredKey(key, provider: name)
        let body = TavilyRequestBody(
            query: query.text,
            maxResults: SearchProviderSupport.clampedCount(query.count, to: Self.countRange),
            timeRange: query.freshness.map(Self.timeRanges.value(for:)),
            includeDomains: query.site.map { [$0] })
        var request = try SearchProviderSupport.jsonPostRequest(to: Self.endpoint, body: body)
        request.setValue(Self.bearerPrefix + key, forHTTPHeaderField: Self.keyHeader)
        return request
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
        let body = try SearchProviderSupport.decodedBody(TavilyResponse.self, from: data, response: response)
        let results = body.results.map { result in
            ProviderResult(title: result.title, url: result.url, snippet: result.content ?? "")
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }
}

/// The JSON body of a Tavily search request. A `nil` field is not in the
/// body, thus the service uses its default.
private struct TavilyRequestBody: Encodable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
        case timeRange = "time_range"
        case includeDomains = "include_domains"
    }

    /// The text of the query.
    let query: String

    /// The maximum number of results.
    let maxResults: Int?

    /// The age limit: `day`, `week`, `month`, or `year`.
    let timeRange: String?

    /// The one domain of the results.
    let includeDomains: [String]?
}

/// The part of a Tavily search response that the provider reads.
private struct TavilyResponse: Decodable {
    /// One result.
    struct SearchResult: Decodable {
        /// The title of the page.
        let title: String

        /// The URL of the page.
        let url: String

        /// A short text from the page, or `nil`.
        let content: String?
    }

    /// The results, in rank order.
    let results: [SearchResult]
}
