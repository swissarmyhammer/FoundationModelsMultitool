// `QueryRoutedAdapter` — a search adapter that sends each query text to its
// own URL, for the tests of the relaxed second run of `WebSearchChain`.
//
// A `WebStub` finds its reply from the URL of a request. A real provider sends
// each query to one fixed URL, thus the stub cannot give one page to the
// exact query and a different page to the relaxed query. This adapter wraps
// an adapter: it makes the request of the wrapped adapter, and then sets the
// URL from the query text. The method, the headers, and the body of the
// request do not change, and the wrapped adapter reads each response.

import Foundation
@testable import FoundationModelsMultitool

/// A search adapter that makes the request of a wrapped adapter and sends it
/// to the URL of its query text.
struct QueryRoutedAdapter: SearchProviderAdapter {
    /// The error of `request` when no URL is set for the query text.
    struct UnroutedQuery: Error, CustomStringConvertible {
        /// The query text that has no URL.
        let text: String

        /// The text of the error.
        var description: String { "no URL is set for the query text \(text)" }
    }

    /// The adapter that makes each request and reads each response.
    private let wrapped: any SearchProviderAdapter

    /// The URL of each query text.
    private let routes: [String: URL]

    /// Makes an adapter.
    ///
    /// - Parameters:
    ///   - wrapped: The adapter that makes each request and reads each
    ///     response.
    ///   - routes: The URL of each query text, keyed by the full text of the
    ///     query.
    init(wrapping wrapped: any SearchProviderAdapter, routes: [String: URL]) {
        self.wrapped = wrapped
        self.routes = routes
    }

    /// The name of the wrapped adapter.
    var name: String { wrapped.name }

    /// The query fields that the wrapped adapter supports.
    var supports: Set<SearchFeature> { wrapped.supports }

    /// `true` when the endpoint of the wrapped adapter is host configuration.
    var isHostConfiguration: Bool { wrapped.isHostConfiguration }

    /// Makes the request of the wrapped adapter, with the URL of the query
    /// text.
    ///
    /// - Parameters:
    ///   - query: The query. Its text selects the URL.
    ///   - key: The key value, or `nil` for a keyless provider.
    /// - Returns: The request.
    /// - Throws: ``UnroutedQuery`` when no URL is set for the query text, or
    ///   the error of the wrapped adapter.
    func request(for query: SearchQuery, key: String?) throws -> URLRequest {
        guard let url = routes[query.text] else { throw UnroutedQuery(text: query.text) }
        var request = try wrapped.request(for: query, key: key)
        request.url = url
        return request
    }

    /// Reads the hits of a response with the wrapped adapter.
    ///
    /// - Parameters:
    ///   - data: The body.
    ///   - response: The response.
    ///   - limit: The maximum number of hits, or `nil` for all hits.
    /// - Returns: The hits of the wrapped adapter.
    /// - Throws: The failure of the wrapped adapter.
    func parse(_ data: Data, response: HTTPURLResponse, limit: Int?) throws(ProviderFailure) -> [WebHit] {
        try wrapped.parse(data, response: response, limit: limit)
    }
}
