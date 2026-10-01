import Testing

@testable import FoundationModelsMultitool

/// The live test of the keyless provider chain, as a host gets it from
/// `WebConfiguration.keyless` (web.md § "Testing", Level 2).
///
/// The chain tries `braveHTML`, then `duckDuckGoHTML`. The test does not
/// assert which of the two gives the hits: a fallback to the second provider
/// is correct behavior of the chain.
///
/// The chain itself applies ``BlockedProviderRule``: it goes to the next
/// provider after a block, thus a blocked provider does not fail this test
/// when the other provider gives results. When no provider gives results, the
/// correction fails the test. The chain tries each keyless provider, thus the
/// rule has no provider to add, and the test sends one search.
@Suite(
    "Live: the keyless chain gives hits from a keyless provider",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct KeylessChainLiveTests {
    /// The names of the two keyless providers. The set is stated here, and
    /// not read from `.keyless`, thus a keyed provider that `.keyless` gets
    /// by mistake fails this test.
    private static let keylessNames: Set<String> = [
        WebSearchProvider.braveHTML.name, WebSearchProvider.duckDuckGoHTML.name,
    ]

    @Test("the keyless chain gives hits, and the provider is braveHTML or duckDuckGoHTML")
    func keylessChainGivesHits() async throws {
        let result = try await LiveSearch.search(providers: WebConfiguration.keyless.providers)

        LiveSearch.expectNoCorrection(result)
        #expect(!result.results.isEmpty, "the keyless chain gave no hit")
        #expect(
            Self.keylessNames.contains(result.provider),
            "the provider \(result.provider) is not one of \(Self.keylessNames.sorted())")
    }
}
