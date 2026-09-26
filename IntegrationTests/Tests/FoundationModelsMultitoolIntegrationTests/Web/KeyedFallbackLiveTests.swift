import Testing

@testable import FoundationModelsMultitool

/// The live test of the fallback from a refused key to a keyless provider
/// (web.md § "Testing", Level 2, the `KeyedFallbackLiveTests` row).
///
/// The providers are `braveAPI` with a key that is not valid, then
/// `braveHTML`. The Brave Search API refuses the key, thus the chain skips
/// `braveAPI` with the refused-key note and gives the hits of `braveHTML`.
/// The test needs no real key, thus it runs on each computer.
@Suite(
    "Live: a refused Brave Search API key falls back to the Brave results page",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct KeyedFallbackLiveTests {
    /// The key that the Brave Search API refuses.
    private static let invalidKey = "invalid-key"

    /// The start of the refused-key note of `braveAPI`. The service gives
    /// the HTTP status after it, for example `422).`.
    private static let refusedKeyNoteStart = "braveAPI: skipped, the API key was refused (HTTP "

    @Test("a braveAPI key that is not valid gives the refused-key note, and the hits come from braveHTML")
    func refusedKeyFallsBackToBraveHTML() async throws {
        let providers: [WebSearchProvider] = [.braveAPI(.literal(Self.invalidKey)), .braveHTML]
        let result = try await LiveSearch.search(providers: providers)

        LiveSearch.expectNoCorrection(result)
        #expect(result.provider == WebSearchProvider.braveHTML.name)
        #expect(
            result.results.count >= LiveSearch.minimumHitCount,
            "expected at least \(LiveSearch.minimumHitCount) hits, got \(result.results.map(\.url))")
        let notes = result.notes ?? []
        #expect(
            notes.contains { $0.hasPrefix(Self.refusedKeyNoteStart) },
            "expected a note that starts with \(Self.refusedKeyNoteStart), got \(notes)")
        LiveSearch.expectNoLeak(of: Self.invalidKey, in: result)
    }
}
