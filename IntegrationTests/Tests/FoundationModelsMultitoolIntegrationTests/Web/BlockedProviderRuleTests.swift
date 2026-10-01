import Testing

@testable import FoundationModelsMultitool

/// The offline checks of ``BlockedProviderRule``: which providers a
/// correction names as blocked, and which providers the second search of the
/// rule gets (card `^kghyac5`, web.md § "Testing", "The blocked provider
/// rule").
///
/// Each check gives a result to the rule. No check sends a request. Thus each
/// check always runs, and it is fast.
@Suite("BlockedProviderRule: a blocked provider is replaced by a keyless provider that was not tried")
struct BlockedProviderRuleTests {
    /// The key of the refused-key cases. The rule does not read it.
    private static let invalidKey = "invalid-key"

    /// The providers of the keyed fallback test.
    private static let keyedFallbackProviders: [WebSearchProvider] = [
        .braveAPI(.literal(invalidKey)), .braveHTML,
    ]

    /// Makes a result with a correction, as the chain gives it when all
    /// providers fail.
    ///
    /// - Parameter failures: The part of the correction for each provider.
    /// - Returns: The result, with no hits.
    private static func correction(_ failures: String...) -> SearchResult {
        let text = ([WebSearchChain.correctionLead] + failures).joined(separator: " ")
        return SearchResult(provider: "", results: [], notes: nil, correction: text)
    }

    @Test("HTTP 429 for braveHTML is a block of braveHTML")
    func rateLimitIsABlock() {
        let result = Self.correction("braveHTML: blocked (HTTP 429).")
        #expect(BlockedProviderRule.blockedProviderNames(in: result, providers: [.braveHTML]) == ["braveHTML"])
    }

    @Test("a challenge page for duckDuckGoHTML is a block of duckDuckGoHTML")
    func challengePageIsABlock() {
        let result = Self.correction("duckDuckGoHTML: blocked by a challenge page.")
        #expect(
            BlockedProviderRule.blockedProviderNames(in: result, providers: [.duckDuckGoHTML])
                == ["duckDuckGoHTML"])
    }

    @Test("a refused key is not a block, and the block of the next provider is")
    func refusedKeyIsNotABlock() {
        let result = Self.correction(
            "braveAPI: the API key was refused (HTTP 422).", "braveHTML: blocked (HTTP 429).")
        #expect(
            BlockedProviderRule.blockedProviderNames(in: result, providers: Self.keyedFallbackProviders)
                == ["braveHTML"])
    }

    @Test("a server error is not a block")
    func serverErrorIsNotABlock() {
        let result = Self.correction("braveHTML: server error (HTTP 503).")
        #expect(BlockedProviderRule.blockedProviderNames(in: result, providers: [.braveHTML]).isEmpty)
    }

    @Test("a result with hits and no correction has no block")
    func resultWithNoCorrectionHasNoBlock() {
        let result = SearchResult(
            provider: "duckDuckGoHTML", results: [], notes: ["braveHTML: skipped, blocked (HTTP 429)."],
            correction: nil)
        #expect(BlockedProviderRule.blockedProviderNames(in: result, providers: [.braveHTML]).isEmpty)
    }

    @Test("a blocked braveHTML is replaced by duckDuckGoHTML")
    func blockedBraveIsReplacedByDuckDuckGo() {
        let replacement = BlockedProviderRule.replacementProviders(for: [.braveHTML], blocked: ["braveHTML"])
        #expect(replacement == [.duckDuckGoHTML])
    }

    @Test("a blocked duckDuckGoHTML is replaced by braveHTML")
    func blockedDuckDuckGoIsReplacedByBrave() {
        let replacement = BlockedProviderRule.replacementProviders(
            for: [.duckDuckGoHTML], blocked: ["duckDuckGoHTML"])
        #expect(replacement == [.braveHTML])
    }

    @Test("a provider that is not blocked keeps its place before the replacement")
    func providerThatIsNotBlockedStays() {
        let replacement = BlockedProviderRule.replacementProviders(
            for: Self.keyedFallbackProviders, blocked: ["braveHTML"])
        #expect(replacement == [.braveAPI(.literal(Self.invalidKey)), .duckDuckGoHTML])
    }

    @Test("when the first search tried each keyless provider, there is no replacement")
    func keylessChainHasNoReplacement() {
        let replacement = BlockedProviderRule.replacementProviders(
            for: WebConfiguration.keyless.providers, blocked: ["braveHTML", "duckDuckGoHTML"])
        #expect(replacement.isEmpty)
    }
}
