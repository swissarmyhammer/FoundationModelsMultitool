import Testing

@testable import FoundationModelsMultitool

/// The live test of the fallback from a refused key to a keyless provider
/// (web.md § "Testing", Level 2, the `KeyedFallbackLiveTests` row).
///
/// The providers are `braveAPI` with a key that is not valid, then
/// `braveHTML`. The Brave Search API refuses the key, thus the chain skips
/// `braveAPI` with the refused-key note and gives the hits of `braveHTML`.
/// The test needs no real key, thus it runs on each computer.
///
/// ``BlockedProviderRule`` decides the outcome, with `braveAPI` excused,
/// because its key is refused by design. On results, the hits come from
/// `braveHTML`. On a recognized block of `braveHTML` (HTTP 429, or a
/// challenge page), the request reached Brave, and the test passes with the
/// checks of the rule. Each other outcome fails. The refused key of
/// `braveAPI` is checked in both outcomes, and the key is not in the result.
@Suite(
    "Live: a refused Brave Search API key falls back to a keyless provider",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct KeyedFallbackLiveTests {
    /// The key that the Brave Search API refuses.
    private static let invalidKey = "invalid-key"

    /// The start of the refused-key note of `braveAPI`, when a later provider
    /// gives the hits. The service gives the HTTP status after it, for
    /// example `422).`.
    private static let refusedKeyNoteStart = "braveAPI: skipped, the API key was refused (HTTP "

    /// The start of the refused-key part of the correction, when no provider
    /// gives hits. The service gives the HTTP status after it.
    private static let refusedKeyCorrectionPart = "braveAPI: the API key was refused (HTTP "

    /// The keyed provider of the test, which the rule excuses.
    private static let keyedProvider = WebSearchProvider.braveAPI(.literal(invalidKey))

    @Test("a braveAPI key that is not valid gives the refused-key note, and the hits come from the keyless provider")
    func refusedKeyFallsBackToKeylessProvider() async throws {
        let providers: [WebSearchProvider] = [Self.keyedProvider, .braveHTML]
        let result = try await LiveSearch.search(providers: providers)

        BlockedProviderRule.expectResultsOrBlock(
            result, providers: providers, excusing: [Self.keyedProvider.name]
        ) {
            #expect(result.provider == WebSearchProvider.braveHTML.name)
            #expect(
                result.results.count >= LiveSearch.minimumHitCount,
                "expected at least \(LiveSearch.minimumHitCount) hits, got \(result.results.map(\.url))")
        }
        Self.expectRefusedKeyReport(in: result)
        LiveSearch.expectNoLeak(of: Self.invalidKey, in: result)
    }

    /// Checks that the result reports the refused key of `braveAPI`.
    ///
    /// The key is refused by design, thus the report is mandatory in each
    /// outcome: a part of the correction when no provider gives hits, and a
    /// note when a later provider gives the hits. Each branch asserts.
    ///
    /// - Parameter result: The result of the `search` verb.
    private static func expectRefusedKeyReport(in result: SearchResult) {
        if let correction = result.correction {
            #expect(
                correction.contains(refusedKeyCorrectionPart),
                "expected a correction part that starts with \(refusedKeyCorrectionPart), got \(correction)")
        } else {
            let notes = result.notes ?? []
            #expect(
                notes.contains { $0.hasPrefix(refusedKeyNoteStart) },
                "expected a note that starts with \(refusedKeyNoteStart), got \(notes)")
        }
    }
}
