// `KagiProvider` — the keyed search provider of the Kagi search API, version 1
// (web.md § "The provider list").
//
// The provider sends `POST /api/v1/search` with a JSON body and the key in the
// `Authorization: Bearer <key>` header. The response puts each kind of result
// in its own list of `data`. The provider reads only `data.search`, the web
// results. It does not read `data.related_search`, thus a related search is
// never a hit. A title or a snippet can hold HTML entities, for example
// `&amp;`, thus the provider reads each as HTML and keeps only its text. The
// API has no age limit value for a year. It has `filters.after`, thus the
// provider sends the day that the age limit gives, from the time of the
// request.

import Foundation

/// The keyed search provider of the Kagi search API.
///
/// The documentation of the API: https://kagi.com/api/docs (the OpenAPI
/// specification: https://redocly-api-docs.kagi.com/api/docs/_bundle/openapi.yaml)
struct KagiProvider: SearchProviderAdapter {
    /// The URL of the search endpoint.
    static let endpoint = "https://kagi.com/api/v1/search"

    /// The header that holds the key.
    static let keyHeader = "Authorization"

    /// The text before the key in ``keyHeader``.
    private static let bearerPrefix = "Bearer "

    /// The counts that the service accepts.
    private static let countRange = 1...1024

    /// The name of the provider: the name of the case `WebSearchProvider.kagi`.
    let name = "kagi"

    /// The query fields that the provider sends: `filters.after`,
    /// `lens.sites_included`, and `limit`.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// `false`: the endpoint is fixed, thus the guard checks the search
    /// request.
    let isHostConfiguration = false

    /// Gives the time of a request. An age limit counts back from it.
    private let now: @Sendable () -> Date

    /// Makes the provider.
    ///
    /// - Parameter now: Gives the time of a request. The default is the
    ///   clock of the system. A test gives a fixed time.
    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Makes a `POST` request with the query as a JSON body and the key in
    /// ``keyHeader``.
    ///
    /// - Parameters:
    ///   - query: The query.
    ///   - key: The key value.
    /// - Returns: The request.
    /// - Throws: ``MissingProviderKey`` when `key` is `nil` or empty,
    ///   ``InvalidStartDate`` when the start date cannot be made,
    ///   ``InvalidProviderEndpoint`` when ``endpoint`` is not a URL, or the
    ///   error of the encoder.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest {
        let key = try SearchProviderSupport.requiredKey(key, provider: name)
        let body = KagiRequestBody(
            query: query.text,
            limit: SearchProviderSupport.clampedCount(query.count, to: Self.countRange),
            filters: try query.freshness.map { KagiRequestBody.Filters(after: try afterDate(for: $0)) },
            lens: query.site.map { KagiLens(sitesIncluded: [$0]) })
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
    /// - Returns: The hits of the web results, with rank 1 first. The title
    ///   and the snippet have no markup and no HTML entities.
    /// - Throws: The failure of the status, `.noResults` for a response with
    ///   no web results, and `.parse` when the body cannot be read.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let body = try SearchProviderSupport.decodedBody(KagiResponse.self, from: data, response: response)
        let results = try (body.data?.search ?? []).map { result throws(ProviderFailure) in
            ProviderResult(
                title: try SearchProviderSupport.text(ofHTML: result.title ?? ""), url: result.url ?? "",
                snippet: try SearchProviderSupport.text(ofHTML: result.snippet ?? ""))
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }

    /// The earliest day of an age limit, in the `date` form of the API, for
    /// example `2026-09-23`.
    ///
    /// - Parameter freshness: The age limit.
    /// - Returns: The day of the time of the request, less the age limit, in
    ///   UTC.
    /// - Throws: ``InvalidStartDate`` when the calendar cannot make the date.
    private func afterDate(for freshness: SearchFreshness) throws -> String {
        let start = try SearchProviderSupport.startDate(of: freshness, before: now())
        return Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().format(start)
    }
}

/// The JSON body of a Kagi search request. A `nil` field is not in the body,
/// thus the service uses its default.
private struct KagiRequestBody: Encodable {
    /// The `filters` object: the date limits of the results.
    struct Filters: Encodable {
        /// The earliest day of the results, in `date` form.
        let after: String
    }

    /// The text of the query.
    let query: String

    /// The maximum number of results.
    let limit: Int?

    /// The date limits of the results.
    let filters: Filters?

    /// The scope of the search: the one domain of the results.
    let lens: KagiLens?
}

/// The `lens` object of a Kagi search request: the scope of the search.
private struct KagiLens: Encodable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case sitesIncluded = "sites_included"
    }

    /// The domains of the results.
    let sitesIncluded: [String]
}

/// The part of a Kagi search response that the provider reads.
private struct KagiResponse: Decodable {
    /// The results of a response, by kind.
    struct ResultLists: Decodable {
        /// The web results, in rank order, or `nil` when the response has
        /// none.
        let search: [SearchResult]?
    }

    /// One web result.
    struct SearchResult: Decodable {
        /// The URL of the page, or `nil`.
        let url: String?

        /// The title of the page, or `nil`. It can hold HTML entities.
        let title: String?

        /// A short text from the page, or `nil`. It can hold HTML entities.
        let snippet: String?
    }

    /// The results, or `nil` when the response has none.
    let data: ResultLists?
}
