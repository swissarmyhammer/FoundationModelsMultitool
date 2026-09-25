// `ExaProvider` — the keyed search provider of the Exa search API (web.md §
// "The provider list").
//
// The provider sends `POST /search` with a JSON body and the key in the
// `x-api-key` header. A response holds no page text unless the request asks
// for it, thus the body asks for `contents.highlights`. The snippet of a hit
// is the highlights of its result. The API has no age limit field. It has a
// `startPublishedDate`, thus the provider sends the date that the age limit
// gives, from the time of the request.

import Foundation

/// The keyed search provider of the Exa search API.
///
/// The documentation of the API: https://exa.ai/docs/reference/search
struct ExaProvider: SearchProviderAdapter {
    /// The URL of the search endpoint.
    static let endpoint = "https://api.exa.ai/search"

    /// The header that holds the key.
    static let keyHeader = "x-api-key"

    /// The counts that the service accepts.
    private static let countRange = 1...100

    /// The text between two highlights of one snippet.
    private static let highlightSeparator = " "

    /// The name of the provider: the name of the case `WebSearchProvider.exa`.
    let name = "exa"

    /// The query fields that the provider sends: `startPublishedDate`,
    /// `includeDomains`, and `numResults`.
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
        let body = ExaRequestBody(
            query: query.text,
            numResults: SearchProviderSupport.clampedCount(query.count, to: Self.countRange),
            includeDomains: query.site.map { [$0] },
            startPublishedDate: try query.freshness.map(startPublishedDate(for:)),
            contents: ExaRequestBody.Contents(highlights: true))
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
    /// - Returns: The hits, with rank 1 first. The snippet is the highlights of
    ///   the result, joined with a space.
    /// - Throws: The failure of the status, `.noResults` for a response with
    ///   no results, and `.parse` when the body cannot be read.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        let body = try SearchProviderSupport.decodedBody(ExaResponse.self, from: data, response: response)
        let results = body.results.map { result in
            ProviderResult(
                title: result.title ?? "", url: result.url,
                snippet: (result.highlights ?? []).joined(separator: Self.highlightSeparator))
        }
        return try SearchProviderSupport.checkedHits(from: results, limit: limit)
    }

    /// The earliest published date of an age limit, in the ISO 8601 form of
    /// the API, for example `2026-09-23T12:00:00.000Z`.
    ///
    /// - Parameter freshness: The age limit.
    /// - Returns: The time of the request, less the age limit, in UTC.
    /// - Throws: ``InvalidStartDate`` when the calendar cannot make the date.
    private func startPublishedDate(for freshness: SearchFreshness) throws -> String {
        let start = try SearchProviderSupport.startDate(of: freshness, before: now())
        return Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt).format(start)
    }
}

/// The JSON body of an Exa search request. A `nil` field is not in the body,
/// thus the service uses its default.
private struct ExaRequestBody: Encodable {
    /// The `contents` object: the page text that the response must hold.
    struct Contents: Encodable {
        /// `true` to get the highlights of each result.
        let highlights: Bool
    }

    /// The text of the query.
    let query: String

    /// The number of results.
    let numResults: Int?

    /// The one domain of the results.
    let includeDomains: [String]?

    /// The earliest published date of the results, in ISO 8601 form.
    let startPublishedDate: String?

    /// The page text that the response must hold.
    let contents: Contents
}

/// The part of an Exa search response that the provider reads.
private struct ExaResponse: Decodable {
    /// One result.
    struct SearchResult: Decodable {
        /// The title of the page, or `nil`.
        let title: String?

        /// The URL of the page.
        let url: String

        /// The highlights of the page, or `nil` when the response has none.
        let highlights: [String]?
    }

    /// The results, in rank order.
    let results: [SearchResult]
}
