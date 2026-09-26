import Testing

@testable import FoundationModelsMultitool

/// The live tests of the DuckDuckGo HTML results page provider, with no
/// fallback (web.md § "Testing", Level 2).
///
/// The providers are `[.duckDuckGoHTML]` only, thus a hit comes from
/// DuckDuckGo or the test fails. When DuckDuckGo changes its markup, this
/// suite fails. That failure is the signal that we want.
///
/// DuckDuckGo can serve its challenge page and not the results, after many
/// requests in a short time. That is a known condition of the live service,
/// and not a defect. Each test records it as a known issue, and does not
/// fail for it. The match is the exact text of the challenge correction, thus
/// all other failures (a markup change, no results, a wrong host) still fail
/// the test. A test does not retry.
@Suite(
    "Live: the DuckDuckGo HTML results page gives stable hits",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct DuckDuckGoHTMLLiveTests {
    /// The one provider of this suite.
    private static let providers: [WebSearchProvider] = [.duckDuckGoHTML]

    /// The correction of the search chain when DuckDuckGo serves its
    /// challenge page. The provider is the only provider, thus the
    /// correction names only it.
    private static let challengeCorrection =
        WebSearchChain.correctionLead + " duckDuckGoHTML: blocked by a challenge page."

    /// The comment of the known issue.
    private static let challengeComment: Comment =
        "DuckDuckGo served its challenge page and not the results. This is a known condition of the live service."

    @Test("the Swift query gives at least 3 https hits, one of them on swift.org")
    func swiftQueryGivesTheSwiftHomePage() async throws {
        try await Self.withChallengePageAsKnownIssue {
            try await LiveSearch.expectSwiftHomePageHit(providers: Self.providers)
        }
    }

    @Test("a site search for developer.apple.com gives only hits under apple.com")
    func siteSearchStaysOnTheSite() async throws {
        try await Self.withChallengePageAsKnownIssue {
            try await LiveSearch.expectHitsOnAppleSite(providers: Self.providers)
        }
    }

    /// Runs one live test, and records the challenge page as a known issue.
    ///
    /// The known issue is intermittent, thus a run with no challenge page
    /// passes. Only an issue with the exact comment of the challenge
    /// correction is known. Each other issue fails the test.
    ///
    /// - Parameter body: The live test.
    /// - Throws: The error that the body throws, when the error does not
    ///   match the challenge correction. Thus the error fails the test.
    private static func withChallengePageAsKnownIssue(_ body: () async throws -> Void) async rethrows {
        try await withKnownIssue(challengeComment, isIntermittent: true) {
            try await body()
        } matching: { issue in
            issue.comments.contains { $0.rawValue == LiveSearch.correctionComment(challengeCorrection).rawValue }
        }
    }
}
