import Testing

@testable import FoundationModelsMultitool

/// The offline checks of ``BlockedProviderRule``: which result of a live
/// search is a pass, and which result is a failure (card `^vn1899e`, web.md
/// § "Testing", "The blocked provider rule").
///
/// Each check gives a result to the rule. No check sends a request. Thus each
/// check always runs, and it is fast.
@Suite("BlockedProviderRule: results or a recognized block pass, and each other outcome fails")
struct BlockedProviderRuleTests {
    /// The key of the refused-key cases. The rule does not read it.
    private static let invalidKey = "invalid-key"

    /// The providers of the keyed fallback test.
    private static let keyedFallbackProviders: [WebSearchProvider] = [
        .braveAPI(.literal(invalidKey)), .braveHTML,
    ]

    /// The part of the correction for a rate limit of `braveHTML`.
    private static let braveRateLimit = "braveHTML: blocked (HTTP 429)."

    /// The part of the correction for a challenge page of `duckDuckGoHTML`.
    private static let duckDuckGoChallenge = "duckDuckGoHTML: blocked by a challenge page."

    /// The part of the correction for a refused key of `braveAPI`.
    private static let refusedKey = "braveAPI: the API key was refused (HTTP 422)."

    /// The reason of a transport error, as the chain writes it after the
    /// name of the provider.
    private static let transportReason =
        "the request to https://search.brave.com/search failed: The network connection was lost."

    /// The reason of an HTTP status that the code does not classify.
    private static let unclassifiedStatusReason = "the response could not be read: the service answered HTTP 418."

    /// The reason of a server error.
    private static let serverErrorReason = "server error (HTTP 503)."

    /// Makes a result with a correction, as the chain gives it when all
    /// providers fail.
    ///
    /// - Parameter failures: The part of the correction for each provider.
    /// - Returns: The result, with no provider, no hit, and no note.
    private static func correction(_ failures: String...) -> SearchResult {
        let text = ([WebSearchChain.correctionLead] + failures).joined(separator: " ")
        return SearchResult(provider: "", results: [], notes: nil, correction: text)
    }

    /// One hit, for a result that has hits.
    private static let hit = WebHit(
        rank: 1, title: "Swift.org", url: "https://www.swift.org/", snippet: "Swift is a programming language.")

    // MARK: The two passes

    @Test("hits with no correction are results")
    func hitsAreResults() {
        let result = SearchResult(provider: "braveHTML", results: [Self.hit], notes: nil, correction: nil)
        #expect(BlockedProviderRule.outcome(of: result, providers: [.braveHTML]) == .results)
    }

    @Test("hits after a skipped blocked provider are results")
    func hitsAfterABlockAreResults() {
        let result = SearchResult(
            provider: "duckDuckGoHTML", results: [Self.hit], notes: ["braveHTML: skipped, blocked (HTTP 429)."],
            correction: nil)
        #expect(BlockedProviderRule.outcome(of: result, providers: WebConfiguration.keyless.providers) == .results)
    }

    @Test("HTTP 429 of braveHTML is a recognized block")
    func rateLimitIsABlock() {
        let result = Self.correction(Self.braveRateLimit)
        #expect(
            BlockedProviderRule.outcome(of: result, providers: [.braveHTML]) == .blocked(providers: ["braveHTML"]))
    }

    @Test("a challenge page of duckDuckGoHTML is a recognized block")
    func challengePageIsABlock() {
        let result = Self.correction(Self.duckDuckGoChallenge)
        #expect(
            BlockedProviderRule.outcome(of: result, providers: [.duckDuckGoHTML])
                == .blocked(providers: ["duckDuckGoHTML"]))
    }

    @Test("a block of each provider of the keyless chain is a recognized block")
    func keylessChainBlockIsABlock() {
        let result = Self.correction(Self.braveRateLimit, Self.duckDuckGoChallenge)
        #expect(
            BlockedProviderRule.outcome(of: result, providers: WebConfiguration.keyless.providers)
                == .blocked(providers: ["braveHTML", "duckDuckGoHTML"]))
    }

    @Test("an excused refused key, then a block, is a recognized block")
    func excusedRefusedKeyThenBlockIsABlock() {
        let result = Self.correction(Self.refusedKey, Self.braveRateLimit)
        #expect(
            BlockedProviderRule.outcome(
                of: result, providers: Self.keyedFallbackProviders, excusing: ["braveAPI"])
                == .blocked(providers: ["braveHTML"]))
    }

    // MARK: The failures

    @Test("a transport error fails")
    func transportErrorFails() {
        let result = Self.correction("braveHTML: \(Self.transportReason)")
        #expect(
            BlockedProviderRule.outcome(of: result, providers: [.braveHTML])
                == .failed(.notABlock(provider: "braveHTML", reason: Self.transportReason)))
    }

    @Test("an unclassified HTTP status fails")
    func unclassifiedStatusFails() {
        let result = Self.correction("braveHTML: \(Self.unclassifiedStatusReason)")
        #expect(
            BlockedProviderRule.outcome(of: result, providers: [.braveHTML])
                == .failed(.notABlock(provider: "braveHTML", reason: Self.unclassifiedStatusReason)))
    }

    @Test("a server error fails")
    func serverErrorFails() {
        let result = Self.correction("braveHTML: \(Self.serverErrorReason)")
        #expect(
            BlockedProviderRule.outcome(of: result, providers: [.braveHTML])
                == .failed(.notABlock(provider: "braveHTML", reason: Self.serverErrorReason)))
    }

    @Test("a block, then a transport error of the next provider, fails")
    func blockThenTransportErrorFails() {
        let result = Self.correction(Self.braveRateLimit, "duckDuckGoHTML: \(Self.transportReason)")
        #expect(
            BlockedProviderRule.outcome(of: result, providers: WebConfiguration.keyless.providers)
                == .failed(.notABlock(provider: "duckDuckGoHTML", reason: Self.transportReason)))
    }

    @Test("a refused key that the test does not excuse fails")
    func refusedKeyThatIsNotExcusedFails() {
        let result = Self.correction(Self.refusedKey, Self.braveRateLimit)
        #expect(
            BlockedProviderRule.outcome(of: result, providers: Self.keyedFallbackProviders)
                == .failed(.notABlock(provider: "braveAPI", reason: "the API key was refused (HTTP 422).")))
    }

    @Test("an excused failure with no block fails")
    func excusedFailureAloneFails() {
        let result = Self.correction(Self.refusedKey)
        #expect(
            BlockedProviderRule.outcome(
                of: result, providers: [.braveAPI(.literal(Self.invalidKey))], excusing: ["braveAPI"])
                == .failed(.noBlock))
    }

    @Test("a correction that does not name each provider in order fails")
    func correctionWithAMissingProviderFails() {
        let result = Self.correction(Self.braveRateLimit)
        #expect(
            BlockedProviderRule.outcome(of: result, providers: WebConfiguration.keyless.providers)
                == .failed(.providersNotReported))
    }

    @Test("a correction beside hits fails, because the hits are invented")
    func correctionBesideHitsFails() {
        let result = SearchResult(
            provider: "", results: [Self.hit], notes: nil,
            correction: [WebSearchChain.correctionLead, Self.braveRateLimit].joined(separator: " "))
        #expect(BlockedProviderRule.outcome(of: result, providers: [.braveHTML]) == .failed(.hitsBesideCorrection))
    }

    @Test("no hit and no correction fails")
    func noHitAndNoCorrectionFails() {
        let result = SearchResult(provider: "braveHTML", results: [], notes: nil, correction: nil)
        #expect(BlockedProviderRule.outcome(of: result, providers: [.braveHTML]) == .failed(.noHitAndNoCorrection))
    }
}
