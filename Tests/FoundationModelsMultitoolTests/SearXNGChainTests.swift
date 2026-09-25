import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for a search chain with the real SearXNG adapter at a local address.
///
/// The base URL of a SearXNG instance is host configuration (web.md §
/// "Security"), thus the chain sends the search request with no guard check,
/// and a loopback base URL is not refused. A `WebStub` answers the request,
/// thus no test uses the network.
@Suite("SearXNGChain")
struct SearXNGChainTests {
    /// The base URL of a SearXNG instance that the host runs on its own
    /// computer.
    private static let localBase = "http://127.0.0.1:8888"

    /// The URL of the search request of the query `swift` to ``localBase``.
    private static let searchURL = "http://127.0.0.1:8888/search?q=swift&format=json"

    @Test("a chain with a SearXNG instance at a loopback address sends the search request and gives hits")
    func loopbackInstanceGivesHits() async throws {
        let base = try #require(URL(string: Self.localBase))
        let body = try KeyedProviderCase.searxng.recordedResponse()
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: ["Content-Type": "application/json"], body: body)
        let stub = WebStub(routes: [Self.searchURL: reply])
        let chain = WebSearchChain(
            providers: [(.searxng(base), SearXNGProvider(base: base))], fetcher: stub.makeFetcher(), environment: [:])
        let outcome = await chain.search(SearchQuery(text: "swift"))
        let expectedHits = try KeyedProviderCase.searxng.parse(body)
        #expect(outcome == .hits(provider: "searxng", hits: expectedHits, notes: []))
        #expect(stub.requestedURLs == [Self.searchURL])
    }
}
