// `BlockedProviderRule` — the one written rule for a blocked search provider
// in the live web search tests (web.md § "Testing", "The blocked provider
// rule", and `IntegrationTests/Package.swift`).

import Testing

@testable import FoundationModelsMultitool

/// The written rule for a blocked provider in the live web search tests.
///
/// **The rule (decided by the user, 2026-10-01, card `^kghyac5`).** A blocked
/// provider (HTTP 429, or a challenge page) does not fail a live test, on the
/// condition that at least one provider gives results. When no provider gives
/// results, the test fails.
///
/// **How a test applies it.** A live search test sends its search through
/// ``search(providers:site:environment:sourceLocation:)``. When the result is
/// a correction that names a block of a provider of the test, the rule does
/// two things:
///
/// 1. It records the correction as a known issue. That is the evidence of the
///    block in the test report.
/// 2. It sends the same query one time to the providers of
///    ``replacementProviders(for:blocked:)``: the providers of the test, with
///    each blocked provider replaced by the keyless providers that the first
///    search did not try.
///
/// The test then runs all its checks on the result of the second search. Thus
/// a hit check that the blocked provider could not pass is done on the hits
/// of a provider that works, and a correction of the second search fails the
/// test. When the first search tried each keyless provider, there is no
/// provider to try, and the test runs its checks on the first result: the
/// correction fails the test.
///
/// This is not a retry, because no provider gets a second request for the
/// query. It is not a skip, because each check of the test runs on a result.
/// A failure that is not a block (a markup change, no results, a server
/// error, a refused key) is not changed by the rule.
enum BlockedProviderRule {
    /// The reasons of a block, as the correction gives them after the name of
    /// the provider and `: `.
    ///
    /// The text is the text of `ProviderFailure.reason` in
    /// `WebSearchChain.swift` for `.rateLimited` and `.challenge`, with the
    /// end period of the correction. The product keeps that text private,
    /// thus the rule states it here.
    static let blockReasons = ["blocked (HTTP 429).", "blocked by a challenge page."]

    /// The comment of the known issue that records a block.
    static let blockComment: Comment =
        "A provider of this test was blocked. By the blocked provider rule (web.md), the test checks the results of a keyless provider that the first search did not try."

    /// The result that a test checks, and the providers of the search that
    /// gave it.
    struct RuledSearch {
        /// The result to check: the result of the first search, or of the
        /// second search when the rule replaced a blocked provider.
        let result: SearchResult

        /// The providers of the search that gave ``result``, in the order to
        /// try.
        let providers: [WebSearchProvider]
    }

    /// Sends the live search of a test under the rule.
    ///
    /// - Parameters:
    ///   - providers: The providers of the test, in the order to try.
    ///   - site: The one host of the hits, or `nil` for all hosts.
    ///   - environment: The environment dictionary that each `.environment`
    ///     key reads.
    ///   - sourceLocation: The location of the call, for the known issue.
    /// - Returns: The first result and `providers` when no provider of the
    ///   test is blocked, or when no keyless provider is left to try. Else the
    ///   result of the second search and its providers.
    /// - Throws: When the verb throws, or when the task is cancelled during
    ///   the wait for a turn of ``LiveSearch/searchSpacing``.
    static func search(
        providers: [WebSearchProvider], site: String? = nil, environment: [String: String] = [:],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> RuledSearch {
        let first = try await LiveSearch.search(providers: providers, site: site, environment: environment)
        let blocked = blockedProviderNames(in: first, providers: providers)
        let replacement = replacementProviders(for: providers, blocked: blocked)
        guard let correction = first.correction, !blocked.isEmpty, !replacement.isEmpty else {
            return RuledSearch(result: first, providers: providers)
        }
        withKnownIssue(blockComment) {
            Issue.record(LiveSearch.correctionComment(correction), sourceLocation: sourceLocation)
        }
        let second = try await LiveSearch.search(providers: replacement, site: site, environment: environment)
        return RuledSearch(result: second, providers: replacement)
    }

    /// The names of the providers that a correction names as blocked.
    ///
    /// - Parameters:
    ///   - result: The result of the `search` verb.
    ///   - providers: The providers of the search.
    /// - Returns: The name of each provider whose part of the correction is
    ///   one of ``blockReasons``, in the order of `providers`. Empty when the
    ///   result has no correction.
    static func blockedProviderNames(in result: SearchResult, providers: [WebSearchProvider]) -> [String] {
        let correction = result.correction ?? ""
        return providers.map(\.name).filter { name in
            blockReasons.contains { reason in correction.contains("\(name): \(reason)") }
        }
    }

    /// The providers of the second search: the providers of the test, with
    /// each blocked provider replaced by the keyless providers that the first
    /// search did not try.
    ///
    /// The providers that are not blocked keep their order, and the keyless
    /// providers come after them, in the order of `WebConfiguration.keyless`.
    /// Thus a test that checks the fallback from a keyed provider still sends
    /// its keyed provider first.
    ///
    /// - Parameters:
    ///   - providers: The providers of the first search.
    ///   - blocked: The names of the blocked providers.
    /// - Returns: The providers of the second search. Empty when no provider
    ///   is blocked, or when the first search tried each keyless provider.
    static func replacementProviders(
        for providers: [WebSearchProvider], blocked: [String]
    ) -> [WebSearchProvider] {
        let triedNames = Set(providers.map(\.name))
        let untriedKeyless = WebConfiguration.keyless.providers.filter { !triedNames.contains($0.name) }
        guard !blocked.isEmpty, !untriedKeyless.isEmpty else { return [] }
        return providers.filter { !blocked.contains($0.name) } + untriedKeyless
    }
}
