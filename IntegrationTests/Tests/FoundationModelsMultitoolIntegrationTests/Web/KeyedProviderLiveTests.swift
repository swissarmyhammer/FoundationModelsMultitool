import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The live tests of the six keyed providers, with the keys from the
/// environment of the test run (web.md § "Testing", Level 2, the
/// `KeyedProviderLiveTests` row).
///
/// **The user's exception to `test-integrity/test-partitioning`.** The user
/// decided on 2026-09-26 (final) that each test of this suite runs only when
/// its variable is set and not empty. When the variable is not set, the test
/// is skipped, not failed, and the skip comment names the variable. This is a
/// written exception to that review rule, for these six tests only. It
/// replaces the earlier decision "always run, fail when the key is missing".
/// No other test reads the environment to decide if it runs.
/// `LiveProviderSettingTests` checks the enable condition with a given
/// dictionary, thus that check needs no real key.
///
/// Each test builds `WebConfiguration.fromEnvironment()`, because that
/// function is the feature under test, and keeps only its own provider. Thus
/// a hit comes from that provider or the test fails. A Swift Testing trait
/// applies to a whole test function, and not to one argument, thus each
/// provider has its own test function and all six share one helper.
@Suite(
    "Live: each keyed provider gives hits with the key from the environment",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct KeyedProviderLiveTests {
    @Test("braveAPI gives hits with BRAVE_SEARCH_API_KEY or BRAVE_API_KEY", .enabled(whenSet: .braveAPI))
    func braveAPIGivesHits() async throws {
        try await Self.expectHits(from: .braveAPI)
    }

    @Test("tavily gives hits with TAVILY_API_KEY", .enabled(whenSet: .tavily))
    func tavilyGivesHits() async throws {
        try await Self.expectHits(from: .tavily)
    }

    @Test("exa gives hits with EXA_API_KEY", .enabled(whenSet: .exa))
    func exaGivesHits() async throws {
        try await Self.expectHits(from: .exa)
    }

    @Test("serper gives hits with SERPER_API_KEY", .enabled(whenSet: .serper))
    func serperGivesHits() async throws {
        try await Self.expectHits(from: .serper)
    }

    @Test("kagi gives hits with KAGI_API_KEY", .enabled(whenSet: .kagi))
    func kagiGivesHits() async throws {
        try await Self.expectHits(from: .kagi)
    }

    @Test("searxng gives hits from the instance at SEARXNG_URL", .enabled(whenSet: .searxng))
    func searxngGivesHits() async throws {
        try await Self.expectHits(from: .searxng)
    }

    /// The shared test of one provider: `fromEnvironment()` has the
    /// provider, ``LiveSearch/swiftQuery`` gives at least
    /// ``LiveSearch/minimumHitCount`` hits from that provider, and no key
    /// value is in the result.
    ///
    /// - Parameters:
    ///   - setting: The provider and its environment variables.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Throws: When `fromEnvironment()` does not have the provider although
    ///   its variable is set, with a message that names the variables; or
    ///   when the verb throws.
    private static func expectHits(
        from setting: LiveProviderSetting, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let environment = ProcessInfo.processInfo.environment
        let configured = WebConfiguration.fromEnvironment(environment).providers
        let provider = try #require(
            configured.first { $0.name == setting.name }, setting.notConfiguredComment,
            sourceLocation: sourceLocation)
        let result = try await LiveSearch.search(providers: [provider], environment: environment)

        LiveSearch.expectNoCorrection(result, sourceLocation: sourceLocation)
        #expect(result.provider == setting.name, sourceLocation: sourceLocation)
        #expect(
            result.results.count >= LiveSearch.minimumHitCount,
            "expected at least \(LiveSearch.minimumHitCount) hits, got \(result.results.map(\.url))",
            sourceLocation: sourceLocation)
        for key in setting.keyValues(in: environment) {
            LiveSearch.expectNoLeak(of: key, in: result, sourceLocation: sourceLocation)
        }
    }
}
