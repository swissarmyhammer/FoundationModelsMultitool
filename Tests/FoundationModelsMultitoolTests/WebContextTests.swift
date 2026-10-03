import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `WebContext`: the map from each search provider to its adapter,
/// and the one fetcher that the reader and the chain share.
///
/// A `WebStub` answers each request, thus no test uses the network.
@Suite("WebContext")
struct WebContextTests {
    /// The base URL of the SearXNG instance of the suite.
    private static let searxngBase = "http://127.0.0.1:8888"

    /// The URL of the search request of the query `swift` to ``searxngBase``.
    private static let searxngSearchURL = "http://127.0.0.1:8888/search?q=swift&format=json"

    /// Each provider case, with a fake key for a keyed provider.
    private static var everyProvider: [WebSearchProvider] {
        get throws {
            let key = WebAPIKey.literal(KeyedProviderCase.fakeKey)
            let base = try #require(URL(string: searxngBase))
            return [
                .braveHTML, .duckDuckGoHTML, .braveAPI(key), .tavily(key), .exa(key), .serper(key), .kagi(key),
                .searxng(base)
            ]
        }
    }

    @Test("each provider maps to the adapter of the same name")
    func eachProviderMapsToItsAdapter() throws {
        for provider in try Self.everyProvider {
            #expect(provider.searchAdapter.name == provider.name)
        }
    }

    @Test("only the searxng provider maps to an adapter of host configuration")
    func onlySearXNGIsHostConfiguration() throws {
        let hostConfigured = try Self.everyProvider.filter { $0.searchAdapter.isHostConfiguration }.map(\.name)
        #expect(hostConfigured == ["searxng"])
    }

    @Test("the searxng adapter sends its request to the base URL of the provider")
    func searxngAdapterUsesTheBaseURL() throws {
        let base = try #require(URL(string: Self.searxngBase))
        let request = try WebSearchProvider.searxng(base).searchAdapter.request(
            for: SearchQuery(text: "swift"), key: nil)
        #expect(request.url?.absoluteString == Self.searxngSearchURL)
    }

    @Test("the search chain of the context sends each request through the stub session")
    func searchChainUsesTheSessionConfiguration() async throws {
        let base = try #require(URL(string: Self.searxngBase))
        let body = try KeyedProviderCase.searxng.recordedResponse()
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: ["Content-Type": "application/json"], body: body)
        let stub = WebStub(routes: [Self.searxngSearchURL: reply])
        let context = WebContext(
            configuration: WebConfiguration(providers: [.searxng(base)]),
            sessionConfiguration: stub.sessionConfiguration, resolver: PublicHostResolver())
        let outcome = await context.searchChain.search(SearchQuery(text: "swift"))
        let expectedHits = try KeyedProviderCase.searxng.parse(body)
        #expect(outcome == .hits(provider: "searxng", hits: expectedHits, notes: []))
        #expect(stub.requestedURLs == [Self.searxngSearchURL])
    }

    @Test("the fetcher of the context uses the fetch policy of the configuration")
    func fetcherUsesTheFetchPolicy() {
        let policy = WebFetchPolicy(userAgent: "WebContextTests")
        let context = WebContext(
            configuration: WebConfiguration(providers: [], fetch: policy),
            sessionConfiguration: .ephemeral, resolver: PublicHostResolver())
        #expect(context.fetcher.policy == policy)
    }
}
