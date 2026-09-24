// `BraveAPIProvider` — the keyed search provider of the Brave Search API
// (web.md § "The provider list").
//
// The provider sends `GET /res/v1/web/search` with the query in the URL and
// the key in the `X-Subscription-Token` header. It reads `web.results`. The
// `web` object is absent when the service has no web results. A description
// holds `<strong>` markup and HTML entities, thus the provider reads it as
// HTML and keeps only its text.

import Foundation
import SwiftSoup

/// The keyed search provider of the Brave Search API.
///
/// The documentation of the API:
/// https://api-dashboard.search.brave.com/api-reference/web/search/get
struct BraveAPIProvider: SearchProviderAdapter {
    /// The URL of the web search endpoint.
    static let endpoint = "https://api.search.brave.com/res/v1/web/search"

    /// The header that holds the key.
    static let keyHeader = "X-Subscription-Token"

    /// The query item of the query text.
    private static let queryItem = "q"

    /// The query item of the number of results.
    private static let countItem = "count"

    /// The query item of the age limit.
    private static let freshnessItem = "freshness"

    /// The counts that the service accepts.
    private static let countRange = 1...20

    /// The name of the provider: the name of the case
    /// `WebSearchProvider.braveAPI`.
    let name = "braveAPI"

    /// The query fields that the provider sends: the `freshness` item, a
    /// `site:` term in the query, and the `count` item.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// Makes a `GET` request with the query in the URL and the key in
    /// ``keyHeader``.
    ///
    /// - Parameters:
    ///   - query: The query. A site adds a `site:<host>` term to the text.
    ///   - key: The key value.
    /// - Returns: The request.
    /// - Throws: ``MissingProviderKey`` when `key` is `nil` or empty, and
    ///   ``InvalidProviderEndpoint`` when the URL cannot be made.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest {
        let key = try SearchProviderSupport.requiredKey(key, provider: name)
        var request = try SearchProviderSupport.jsonGetRequest(to: Self.endpoint, items: Self.queryItems(of: query))
        request.setValue(key, forHTTPHeaderField: Self.keyHeader)
        return request
    }

    /// Reads the hits of a response.
    ///
    /// - Parameters:
    ///   - data: The JSON body of the response.
    ///   - response: The response. Its status comes first.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits, with rank 1 first. The snippet is the text of the
    ///   description, with no markup.
    /// - Throws: The failure of the status, `.noResults` for a response with
    ///   no web results, and `.parse` when the body cannot be read.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let body = try SearchProviderSupport.decodedBody(BraveResponse.self, from: data, response: response)
        let results = try (body.web?.results ?? []).map { result throws(ProviderFailure) in
            ProviderResult(
                title: try Self.text(ofHTML: result.title), url: result.url,
                snippet: try Self.text(ofHTML: result.description ?? ""))
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }

    /// The query items of a query, in order.
    ///
    /// - Parameter query: The query.
    /// - Returns: The `q` item, then the `count` item and the `freshness`
    ///   item when the query sets them.
    private static func queryItems(of query: SearchQuery) -> [(name: String, value: String)] {
        let count = SearchProviderSupport.clampedCount(query.count, to: countRange)
        let countItems = count.map { [(name: countItem, value: String($0))] } ?? []
        let freshnessItems = query.freshness.map { [(name: freshnessItem, value: $0.braveFreshnessValue)] } ?? []
        return [(name: queryItem, value: query.textWithSiteTerm)] + countItems + freshnessItems
    }

    /// The text of an HTML fragment, with its markup removed and its entities
    /// decoded.
    ///
    /// - Parameter html: The HTML fragment.
    /// - Returns: The text.
    /// - Throws: `.parse` when SwiftSoup cannot read the fragment.
    private static func text(ofHTML html: String) throws(ProviderFailure) -> String {
        try SearchProviderSupport.reading { try SwiftSoup.parseBodyFragment(html).text() }
    }
}

/// The part of a Brave Search API response that the provider reads.
private struct BraveResponse: Decodable {
    /// The web results of a response.
    struct Web: Decodable {
        /// The results, in rank order.
        let results: [WebResult]
    }

    /// One web result.
    struct WebResult: Decodable {
        /// The title of the page. It can hold HTML entities.
        let title: String

        /// The URL of the page.
        let url: String

        /// The description of the page, with `<strong>` markup, or `nil`.
        let description: String?
    }

    /// The web results, or `nil` when the service has none.
    let web: Web?
}

private extension SearchFreshness {
    /// The value of the `freshness` query item of the Brave Search API for
    /// this age limit.
    var braveFreshnessValue: String {
        switch self {
        case .day: "pd"
        case .week: "pw"
        case .month: "pm"
        case .year: "py"
        }
    }
}
