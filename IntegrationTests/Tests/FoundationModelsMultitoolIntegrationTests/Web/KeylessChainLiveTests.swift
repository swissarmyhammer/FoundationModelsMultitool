import Testing

@testable import FoundationModelsMultitool

/// The live test of the keyless provider chain, as a host gets it from
/// `WebConfiguration.keyless` (web.md § "Testing", Level 2).
///
/// The chain tries `braveHTML`, then `duckDuckGoHTML`. The test does not
/// assert which of the two gives the hits: a fallback to the second provider
/// is correct behavior of the chain.
///
/// ``BlockedProviderRule`` decides the outcome. The chain goes to the next
/// provider after a block, thus one blocked provider gives results from the
/// other provider. When each provider blocks the request, the requests
/// reached both providers: the test passes when the correction reports the
/// block of `braveHTML`, then of `duckDuckGoHTML`, and the result holds no
/// hit. Each other outcome fails. The test sends one search.
@Suite(
    "Live: the keyless chain gives hits from a keyless provider",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
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
        let providers = WebConfiguration.keyless.providers
        let result = try await LiveSearch.search(providers: providers)

        #expect(Set(providers.map(\.name)) == Self.keylessNames)
        BlockedProviderRule.expectResultsOrBlock(result, providers: providers) {
            #expect(
                Self.keylessNames.contains(result.provider),
                "the provider \(result.provider) is not one of \(Self.keylessNames.sorted())")
        }
    }
}
