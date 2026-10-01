import Testing

@testable import FoundationModelsMultitool

/// The live tests of the Brave results page provider, with no fallback
/// (web.md § "Testing", Level 2).
///
/// The providers are `[.braveHTML]` only, thus when Brave answers, each hit
/// comes from Brave. When Brave changes its markup, this suite fails. That
/// failure is the signal that we want.
///
/// When Brave blocks the request (HTTP 429, or a challenge page),
/// ``BlockedProviderRule`` decides the case: the test records the block as a
/// known issue, and does the same checks on the hits of a keyless provider
/// that the first search did not try. When that provider gives no results
/// too, the test fails.
@Suite(
    "Live: the Brave results page gives stable hits",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct BraveHTMLLiveTests {
    /// The one provider of this suite.
    private static let providers: [WebSearchProvider] = [.braveHTML]

    @Test("the Swift query gives at least 3 https hits, one of them on swift.org")
    func swiftQueryGivesTheSwiftHomePage() async throws {
        try await LiveSearch.expectSwiftHomePageHit(providers: Self.providers)
    }

    @Test("a site search for developer.apple.com gives only hits under apple.com")
    func siteSearchStaysOnTheSite() async throws {
        try await LiveSearch.expectHitsOnAppleSite(providers: Self.providers)
    }
}
