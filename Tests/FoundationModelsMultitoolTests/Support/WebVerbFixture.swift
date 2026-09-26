// `WebVerbFixture` — the shared setup of the tests of the two web verbs,
// `search` and `fetch`.
//
// Each test makes one `WebStub` and one `WebContext` over it. The context
// uses the stub session and a resolver that gives a public address for each
// host, thus no request and no lookup goes to the network. Each verb call goes
// through `WebVerbCall` of `MultitoolTestSupport`, the call that the live
// suites of `WebIntegrationTests/` make too.

import Foundation
@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport
import Testing

/// A stub and the web context that sends each request to it.
///
/// The fixture keeps the stub, thus the stub stays registered while the test
/// uses the context.
struct WebVerbFixture {
    /// The URL of the page that the fetch tests load.
    static let pageURL = "https://site.example/page"

    /// The query of the search tests.
    static let query = "swift"

    /// The content type of a JSON response.
    static let jsonContentType = "application/json"

    /// The header of a JSON response.
    static let jsonHeaders = ["Content-Type": jsonContentType]

    /// The stub that answers each request of ``context``.
    let stub: WebStub

    /// The web context of the test.
    let context: WebContext

    /// Makes a fixture.
    ///
    /// - Parameters:
    ///   - routes: The reply for each URL, keyed by the absolute URL text.
    ///   - providers: The search providers, in the order to try. The default
    ///     is the SearXNG instance of ``searxngProvider()``.
    ///   - policy: The fetch policy. The default is the default policy.
    /// - Throws: When the base URL of the SearXNG instance does not parse.
    init(
        routes: [String: WebStubReply] = [:],
        providers: [WebSearchProvider]? = nil,
        policy: WebFetchPolicy = WebFetchPolicy()
    ) throws {
        stub = WebStub(routes: routes)
        let configuration = try WebConfiguration(providers: providers ?? [Self.searxngProvider()], fetch: policy)
        context = WebContext(
            configuration: configuration, sessionConfiguration: stub.sessionConfiguration,
            resolver: PublicHostResolver())
    }

    /// The SearXNG provider of the suite, at the base URL of
    /// `KeyedProviderCase.searxngBase`.
    ///
    /// - Returns: The provider.
    /// - Throws: When the base URL does not parse.
    static func searxngProvider() throws -> WebSearchProvider {
        try .searxng(#require(URL(string: KeyedProviderCase.searxngBase)))
    }

    /// The URL of the SearXNG search request of a query, as the SearXNG
    /// adapter makes it.
    ///
    /// - Parameter searchQuery: The query. The default is ``query`` with no
    ///   other field.
    /// - Returns: The absolute URL text.
    /// - Throws: When the adapter cannot make the request.
    static func searxngSearchURL(for searchQuery: SearchQuery = SearchQuery(text: query)) throws -> String {
        let request = try searxngProvider().searchAdapter.request(for: searchQuery, key: nil)
        return try #require(request.url?.absoluteString)
    }

    /// A SearXNG reply that holds a number of results.
    ///
    /// - Parameter count: The number of results. Result `n` has the URL
    ///   `https://result.example/n`.
    /// - Returns: The reply, with status 200.
    static func searxngReply(resultCount count: Int) -> WebStubReply {
        let results = (0..<count).map { position in
            let index = position + 1
            return FixtureResult(
                title: "Result \(index)", url: "https://result.example/\(index)", snippet: "Snippet \(index)")
        }
        let body = KeyedProviderCase.searxng.responseBody(results)
        return .respond(status: WebStub.okStatus, headers: jsonHeaders, body: Data(body.utf8))
    }

    /// A reply with a status, a content type, and a text body.
    ///
    /// - Parameters:
    ///   - status: The HTTP status. The default is 200.
    ///   - contentType: The `Content-Type` header.
    ///   - body: The body text, in UTF-8.
    /// - Returns: The reply.
    static func textReply(status: Int = WebStub.okStatus, contentType: String, body: String) -> WebStubReply {
        .respond(status: status, headers: ["Content-Type": contentType], body: Data(body.utf8))
    }

    /// Calls the `search` verb.
    ///
    /// - Parameters:
    ///   - query: The query text.
    ///   - count: The number of results, or `nil`.
    ///   - freshness: The age limit, or `nil`.
    ///   - site: The one host of the results, or `nil`.
    /// - Returns: The result of the verb.
    /// - Throws: When the verb throws. The verb must not throw.
    func search(
        _ query: String = query, count: Int? = nil, freshness: String? = nil, site: String? = nil
    ) async throws -> SearchResult {
        try await WebVerbCall.search(query, count: count, freshness: freshness, site: site, context: context)
    }

    /// Calls the `fetch` verb.
    ///
    /// - Parameters:
    ///   - url: The URL text. The default is ``pageURL``.
    ///   - format: The format name, or `nil`.
    ///   - offset: The character offset, or `nil`.
    ///   - maxCharacters: The window size, or `nil`.
    ///   - timeout: The time limit in seconds, or `nil`.
    /// - Returns: The result of the verb.
    /// - Throws: When the verb throws. The verb must not throw.
    func fetch(
        _ url: String = pageURL, format: String? = nil, offset: Int? = nil, maxCharacters: Int? = nil,
        timeout: Int? = nil
    ) async throws -> FetchResult {
        try await WebVerbCall.fetch(
            url, format: format, offset: offset, maxCharacters: maxCharacters, timeout: timeout, context: context)
    }
}
