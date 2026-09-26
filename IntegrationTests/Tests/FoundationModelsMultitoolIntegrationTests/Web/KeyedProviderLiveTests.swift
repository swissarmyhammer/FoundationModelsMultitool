import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The live tests of the six keyed providers, with the keys from the
/// environment of the test run (web.md § "Testing", Level 2, the
/// `KeyedProviderLiveTests` row).
///
/// Each test ALWAYS runs. A test reads its variable from the environment as
/// configuration, and never to decide if it runs (web.md § "Testing", "The
/// environment rule"). When the variable is not set, the test fails with a
/// message that names the variable. It does not skip.
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
    @Test("braveAPI gives hits with BRAVE_SEARCH_API_KEY or BRAVE_API_KEY")
    func braveAPIGivesHits() async throws {
        try await Self.expectHits(
            from: LiveProviderSetting(name: "braveAPI", variables: ["BRAVE_SEARCH_API_KEY", "BRAVE_API_KEY"]))
    }

    @Test("tavily gives hits with TAVILY_API_KEY")
    func tavilyGivesHits() async throws {
        try await Self.expectHits(from: LiveProviderSetting(name: "tavily", variables: ["TAVILY_API_KEY"]))
    }

    @Test("exa gives hits with EXA_API_KEY")
    func exaGivesHits() async throws {
        try await Self.expectHits(from: LiveProviderSetting(name: "exa", variables: ["EXA_API_KEY"]))
    }

    @Test("serper gives hits with SERPER_API_KEY")
    func serperGivesHits() async throws {
        try await Self.expectHits(from: LiveProviderSetting(name: "serper", variables: ["SERPER_API_KEY"]))
    }

    @Test("kagi gives hits with KAGI_API_KEY")
    func kagiGivesHits() async throws {
        try await Self.expectHits(from: LiveProviderSetting(name: "kagi", variables: ["KAGI_API_KEY"]))
    }

    @Test("searxng gives hits from the instance at SEARXNG_URL")
    func searxngGivesHits() async throws {
        try await Self.expectHits(
            from: LiveProviderSetting(name: "searxng", variables: ["SEARXNG_URL"], holdsKey: false))
    }

    /// The shared test of one provider: `fromEnvironment()` has the
    /// provider, ``LiveSearch/swiftQuery`` gives at least
    /// ``LiveSearch/minimumHitCount`` hits from that provider, and no key
    /// value is in the result.
    ///
    /// - Parameters:
    ///   - setting: The provider and its environment variables.
    ///   - sourceLocation: The location of the call, for the failure record.
    /// - Throws: When `fromEnvironment()` does not have the provider, with a
    ///   message that names the variables; or when the verb throws.
    private static func expectHits(
        from setting: LiveProviderSetting, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let environment = ProcessInfo.processInfo.environment
        let configured = WebConfiguration.fromEnvironment(environment).providers
        let provider = try #require(
            configured.first { $0.name == setting.name }, setting.missingComment, sourceLocation: sourceLocation)
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

/// One keyed provider of the live tests, and the environment variables that
/// configure it.
private struct LiveProviderSetting {
    /// The name of the provider, for example `braveAPI`.
    let name: String

    /// The environment variables that can configure the provider, in the
    /// order that `fromEnvironment()` reads them.
    let variables: [String]

    /// `true` when each variable holds an API key. `false` for `searxng`,
    /// whose variable holds the base URL of an instance and not a key.
    var holdsKey = true

    /// The comment of the failure when `fromEnvironment()` does not have the
    /// provider. It names each variable.
    var missingComment: Comment {
        let names = variables.joined(separator: " or ")
        return Comment(
            rawValue: "\(name) is not configured: set \(names) in the environment of the test run. "
                + "This test always runs, and it fails when the variable is not set.")
    }

    /// The key values that the environment holds for the provider.
    ///
    /// - Parameter environment: The environment of the test run.
    /// - Returns: The value of each variable that is set and not empty, or no
    ///   value when the variables hold no key.
    func keyValues(in environment: [String: String]) -> [String] {
        guard holdsKey else { return [] }
        return variables.compactMap { environment[$0] }.filter { !$0.isEmpty }
    }
}
