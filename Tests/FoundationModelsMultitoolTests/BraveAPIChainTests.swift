import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for a search chain with the real Brave Search API adapter.
///
/// The live Brave Search API answers HTTP 422 with the error code
/// `SUBSCRIPTION_TOKEN_INVALID` for a token that is not valid (web.md §
/// "Fallback"). The chain must then skip `braveAPI` with the refused-key note,
/// and go to the next provider. A `WebStub` answers each request, thus no test
/// uses the network.
@Suite("BraveAPIChain")
struct BraveAPIChainTests {
    /// The key of the `braveAPI` provider in the tests.
    private static let key = "sk-test-brave-chain-key-0123"

    /// The URL of the Brave Search API request of the query `swift`.
    private static let braveSearchURL = "https://api.search.brave.com/res/v1/web/search?q=swift"

    /// The URL of the endpoint of the fake second provider.
    private static let fallbackURL = "https://fallback.example/search"

    /// The status of the Brave answer to a token that is not valid.
    private static let invalidTokenStatus = 422

    /// The body of the Brave answer to a token that is not valid. The live
    /// service gave this body on 2026-09-26.
    private static let invalidTokenBody = """
        {"error":{"code":"SUBSCRIPTION_TOKEN_INVALID","detail":"The provided subscription token is invalid.",\
        "meta":{"component":"authentication"},"status":422},"type":"ErrorResponse"}
        """

    /// A Brave answer of HTTP 422 with an error code that is not a refused
    /// token.
    private static let otherErrorBody = """
        {"error":{"code":"VALIDATION","detail":"Unable to validate request parameter(s).","status":422},\
        "type":"ErrorResponse"}
        """

    /// The one hit of the fake second provider, in its line format.
    private static let fallbackLine = "Fallback\thttps://result.example/1"

    /// The hit that ``fallbackLine`` gives.
    private static let fallbackHit = WebHit(rank: 1, title: "Fallback", url: "https://result.example/1", snippet: "")

    /// Runs the query `swift` over `braveAPI` with ``key``, then a fake
    /// `duckDuckGoHTML` provider that gives ``fallbackHit``.
    ///
    /// - Parameter braveReply: The reply to the Brave Search API request.
    /// - Returns: The outcome of the search.
    private static func searchAfterBrave(gets braveReply: WebStubReply) async -> SearchOutcome {
        let fallback = FakeSearchAdapter(name: "duckDuckGoHTML", endpoint: URL(string: fallbackURL))
        let stub = WebStub(routes: [
            braveSearchURL: braveReply,
            fallbackURL: .respond(
                status: WebStub.okStatus, headers: ["Content-Type": "text/plain"], body: Data(fallbackLine.utf8))
        ])
        let chain = WebSearchChain(
            providers: [(.braveAPI(.literal(key)), BraveAPIProvider()), (.duckDuckGoHTML, fallback)],
            fetcher: stub.makeFetcher(), environment: [:])
        return await chain.search(SearchQuery(text: "swift"))
    }

    /// A JSON reply with ``invalidTokenStatus`` and `body`.
    ///
    /// - Parameter body: The JSON body.
    /// - Returns: The reply.
    private static func invalidTokenStatusReply(_ body: String) -> WebStubReply {
        .respond(status: invalidTokenStatus, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    @Test("a Brave answer of HTTP 422 SUBSCRIPTION_TOKEN_INVALID skips braveAPI with the refused-key note")
    func invalidTokenIsRefusedKey() async {
        let outcome = await Self.searchAfterBrave(gets: Self.invalidTokenStatusReply(Self.invalidTokenBody))
        #expect(
            outcome
                == .hits(
                    provider: "duckDuckGoHTML", hits: [Self.fallbackHit],
                    notes: ["braveAPI: skipped, the API key was refused (HTTP 422)."]))
    }

    @Test("a Brave answer of HTTP 422 with another error code skips braveAPI with the read-failure note")
    func otherInvalidStatusIsReadFailure() async {
        let outcome = await Self.searchAfterBrave(gets: Self.invalidTokenStatusReply(Self.otherErrorBody))
        #expect(
            outcome
                == .hits(
                    provider: "duckDuckGoHTML", hits: [Self.fallbackHit],
                    notes: ["braveAPI: skipped, the response could not be read: the service answered HTTP 422."]))
    }
}
