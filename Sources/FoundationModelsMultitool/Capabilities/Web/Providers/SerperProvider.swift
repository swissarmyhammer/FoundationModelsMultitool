// `SerperProvider` — the keyed search provider of the Serper Google search API
// (web.md § "The provider list").
//
// The provider sends `POST /search` with a JSON body and the key in the
// `X-API-KEY` header. The body has no site field, thus a site adds a
// `site:<host>` term to `q`. The age limit is the Google `tbs` value
// `qdr:<unit>`. The provider reads `organic`, and the snippet of a hit is the
// `snippet` field of its result. It does not read `relatedSearches`,
// `peopleAlsoAsk`, or `knowledgeGraph`.

import Foundation

/// The keyed search provider of the Serper Google search API.
///
/// The documentation of the API: https://serper.dev/playground. On 2026-09-25
/// that page did not show its code samples to a fetch. The fields here agree
/// with the Serper clients of LiteLLM (https://docs.litellm.ai/docs/search/serper)
/// and LangChain.
struct SerperProvider: SearchProviderAdapter {
    /// The URL of the search endpoint.
    static let endpoint = "https://google.serper.dev/search"

    /// The header that holds the key.
    static let keyHeader = "X-API-KEY"

    /// The counts that the service accepts.
    private static let countRange = 1...100

    /// The name of the provider: the name of the case
    /// `WebSearchProvider.serper`.
    let name = "serper"

    /// The query fields that the provider sends: `tbs`, a `site:` term in
    /// `q`, and `num`.
    let supports: Set<SearchFeature> = [.freshness, .site, .count]

    /// Makes a `POST` request with the query as a JSON body and the key in
    /// ``keyHeader``.
    ///
    /// - Parameters:
    ///   - query: The query. A site adds a `site:<host>` term to the text.
    ///   - key: The key value.
    /// - Returns: The request.
    /// - Throws: ``MissingProviderKey`` when `key` is `nil` or empty,
    ///   ``InvalidProviderEndpoint`` when ``endpoint`` is not a URL, or the
    ///   error of the encoder.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest {
        let key = try SearchProviderSupport.requiredKey(key, provider: name)
        let body = SerperRequestBody(
            query: query.textWithSiteTerm,
            num: SearchProviderSupport.clampedCount(query.count, to: Self.countRange),
            tbs: query.freshness?.serperTimeFilter)
        var request = try SearchProviderSupport.jsonPostRequest(to: Self.endpoint, body: body)
        request.setValue(key, forHTTPHeaderField: Self.keyHeader)
        return request
    }

    /// Reads the hits of a response.
    ///
    /// - Parameters:
    ///   - data: The JSON body of the response.
    ///   - response: The response. Its status comes first.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits of the organic results, with rank 1 first. The
    ///   snippet is the `snippet` of the result.
    /// - Throws: The failure of the status, `.noResults` for a response with
    ///   no organic results, and `.parse` when the body cannot be read.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let body = try SearchProviderSupport.decodedBody(SerperResponse.self, from: data, response: response)
        let results = (body.organic ?? []).map { result in
            ProviderResult(title: result.title ?? "", url: result.link ?? "", snippet: result.snippet ?? "")
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }
}

/// The JSON body of a Serper search request. A `nil` field is not in the
/// body, thus the service uses its default.
private struct SerperRequestBody: Encodable {
    /// The documented field names.
    enum CodingKeys: String, CodingKey {
        case query = "q"
        case num
        case tbs
    }

    /// The text of the query, with a `site:` term when the query has a site.
    let query: String

    /// The number of results.
    let num: Int?

    /// The age limit, for example `qdr:w`.
    let tbs: String?
}

/// The part of a Serper search response that the provider reads.
private struct SerperResponse: Decodable {
    /// One organic result.
    struct OrganicResult: Decodable {
        /// The title of the page, or `nil`.
        let title: String?

        /// The URL of the page, or `nil`.
        let link: String?

        /// A short text from the page, or `nil`.
        let snippet: String?
    }

    /// The organic results, in rank order, or `nil` when the response has
    /// none.
    let organic: [OrganicResult]?
}

private extension SearchFreshness {
    /// The value of the `tbs` field of the Serper search API for this age
    /// limit.
    var serperTimeFilter: String {
        switch self {
        case .day: "qdr:d"
        case .week: "qdr:w"
        case .month: "qdr:m"
        case .year: "qdr:y"
        }
    }
}
