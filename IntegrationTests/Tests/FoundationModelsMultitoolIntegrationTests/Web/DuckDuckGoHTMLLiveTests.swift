import Testing

@testable import FoundationModelsMultitool

/// The live tests of the DuckDuckGo HTML results page provider, with no
/// fallback (web.md § "Testing", Level 2).
///
/// The providers are `[.duckDuckGoHTML]` only, thus when DuckDuckGo answers,
/// each hit comes from DuckDuckGo. When DuckDuckGo changes its markup, this
/// suite fails. That failure is the signal that we want.
///
/// DuckDuckGo can serve its challenge page and not the results, after many
/// requests in a short time. ``BlockedProviderRule`` decides the outcome. When
/// DuckDuckGo gives results, the test checks the hits. When DuckDuckGo blocks
/// the request (a challenge page, or HTTP 429), the request reached
/// DuckDuckGo: the test passes when the correction reports the block of
/// `duckDuckGoHTML` and the result holds no hit. All other outcomes (a markup
/// change, no results, a transport error, a wrong host) fail the test. A test
/// does not retry.
@Suite(
    "Live: the DuckDuckGo HTML results page gives stable hits",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct DuckDuckGoHTMLLiveTests {
    /// The one provider of this suite.
    private static let providers: [WebSearchProvider] = [.duckDuckGoHTML]

    @Test("the Swift query gives at least 3 https hits, one of them on swift.org")
    func swiftQueryGivesTheSwiftHomePage() async throws {
        try await LiveSearch.expectSwiftHomePageHit(providers: Self.providers)
    }

    @Test("a site search for developer.apple.com gives only hits under apple.com")
    func siteSearchStaysOnTheSite() async throws {
        try await LiveSearch.expectHitsOnAppleSite(providers: Self.providers)
    }
}
