// `BlockedProviderRule` — the one written rule for a blocked search provider
// in the live web tests (web.md § "Testing", "The blocked provider rule", and
// `IntegrationTests/Package.swift`).

import Testing

@testable import FoundationModelsMultitool

/// The written rule for the result of a live web search.
///
/// **The rule (decided by the user, 2026-10-02, card `^vn1899e`).** "If the
/// provider blocks, we managed to talk to it, didn't we." A block that the
/// code recognizes (HTTP 429, or a challenge page) proves that the request
/// reached the provider. Thus a live web test passes on exactly one of two
/// outcomes:
///
/// 1. **Results.** The search gave hits. The test runs its checks of the hits.
/// 2. **A recognized block.** The search gave a correction, and the rule
///    checks what the code controls: the correction names each provider of
///    the search in order (the chain went on to the next provider as
///    designed), each part names the provider and the kind of block, the
///    correction ends with a next step of the chain, and the result holds no
///    hit, no provider, and no note (no invented hits).
///
/// Each other outcome fails the test: a transport error, a timeout, a
/// response that the code cannot read, an HTTP status that is not a block, no
/// hit with no correction, a correction that does not report each provider,
/// or a correction with no next step.
///
/// This is not a skip and not a known issue: a block is a pass with checks.
/// It is not a retry: the test sends one search, and the rule reads its
/// result.
enum BlockedProviderRule {
    /// The reasons of a block, as the correction gives them after the name of
    /// the provider and `: `.
    ///
    /// The text is the text of `ProviderFailure.reason` in
    /// `WebSearchChain.swift` for `.rateLimited` and `.challenge`, with the
    /// end period of the correction. The product keeps that text private,
    /// thus the rule states it here.
    private static let blockReasons: Set<String> = ["blocked (HTTP 429).", "blocked by a challenge page."]

    /// The text between the name of a provider and its reason in the
    /// correction.
    private static let reasonSeparator = ": "

    /// The text between two parts of the correction.
    private static let partSeparator = " "

    /// The sentences that the chain puts at the end of a correction, after
    /// the part of the last provider. The rule removes the sentence before
    /// it reads the parts, thus the sentence is not in the reason of the
    /// last provider.
    private static let nextSteps = [WebSearchChain.correctionNextStep, WebSearchChain.correctionWaitStep]

    /// The first word of the line that tells the outcome of one live search
    /// in the test log.
    private static let traceLinePrefix = "LIVE-SEARCH"

    /// The outcome of one live search under the rule.
    enum Outcome: Equatable {
        /// The search gave hits. The test runs its checks of the hits.
        case results

        /// The search reached each provider, and the named providers blocked
        /// it. The rule did the checks of the block, and the test passes.
        case blocked(providers: [String])

        /// The result is not results and not a recognized block. The test
        /// fails.
        case failed(Failure)
    }

    /// Why the result of a live search fails the rule.
    enum Failure: Equatable {
        /// The search gave no hit and no correction.
        case noHitAndNoCorrection

        /// The search gave a correction, and also hits, a provider, or notes.
        /// A correction has none of them, thus they are invented.
        case hitsBesideCorrection

        /// The correction does not name each provider of the search in
        /// order, with the lead sentence of the chain first.
        case providersNotReported

        /// The correction does not end with a next step of the chain:
        /// `WebSearchChain.correctionNextStep` or
        /// `WebSearchChain.correctionWaitStep`.
        case nextStepMissing

        /// The correction gives this reason for this provider, and the reason
        /// is not a block. Examples: a transport error, a timeout, a server
        /// error, a response that the code cannot read.
        case notABlock(provider: String, reason: String)

        /// Each part of the correction is a failure that the test excused,
        /// thus no provider blocked the search.
        case noBlock
    }

    /// One part of the correction: a provider and the reason that the chain
    /// gives for it.
    private struct ProviderFailurePart {
        /// The name of the provider.
        let provider: String

        /// The reason, with its end period, for example `blocked (HTTP 429).`.
        let reason: String
    }

    /// Classifies the result of one live search.
    ///
    /// - Parameters:
    ///   - result: The result of the `search` verb.
    ///   - providers: The providers of the search, in the order to try.
    ///   - excused: The names of the providers whose failure the test expects
    ///     by design, for example a key that is not valid. The test checks
    ///     the failure of such a provider itself.
    /// - Returns: ``Outcome/results`` for hits with no correction,
    ///   ``Outcome/blocked(providers:)`` for a recognized block, else
    ///   ``Outcome/failed(_:)`` with the reason.
    static func outcome(
        of result: SearchResult, providers: [WebSearchProvider], excusing excused: Set<String> = []
    ) -> Outcome {
        guard let correction = result.correction else {
            return result.results.isEmpty ? .failed(.noHitAndNoCorrection) : .results
        }
        guard result.results.isEmpty, result.provider.isEmpty, result.notes == nil else {
            return .failed(.hitsBesideCorrection)
        }
        guard let failures = failureText(of: correction) else {
            return .failed(.nextStepMissing)
        }
        guard let parts = failureParts(of: failures, providers: providers.map(\.name)) else {
            return .failed(.providersNotReported)
        }
        let judged = parts.filter { !excused.contains($0.provider) }
        if let unrecognized = judged.first(where: { !blockReasons.contains($0.reason) }) {
            return .failed(.notABlock(provider: unrecognized.provider, reason: unrecognized.reason))
        }
        guard !judged.isEmpty else { return .failed(.noBlock) }
        return .blocked(providers: judged.map(\.provider))
    }

    /// Applies the rule to the result of one live search.
    ///
    /// On results, the test runs `checkResults`. On a recognized block, the
    /// rule has done the checks, and the test passes. On each other outcome,
    /// the rule records one failure that names the cause and gives the
    /// result. For results and for a block, the rule writes one
    /// ``traceLinePrefix`` line to standard out, thus a log reader sees
    /// which outcome each live search gave.
    ///
    /// - Parameters:
    ///   - result: The result of the `search` verb.
    ///   - providers: The providers of the search, in the order to try.
    ///   - excused: The names of the providers whose failure the test expects
    ///     by design. See ``outcome(of:providers:excusing:)``.
    ///   - sourceLocation: The location of the call, for the failure record.
    ///   - checkResults: The checks of the hits of the test.
    /// - Throws: What `checkResults` throws.
    static func expectResultsOrBlock(
        _ result: SearchResult, providers: [WebSearchProvider], excusing excused: Set<String> = [],
        sourceLocation: SourceLocation = #_sourceLocation, checkResults: () throws -> Void
    ) rethrows {
        switch outcome(of: result, providers: providers, excusing: excused) {
        case .results:
            reportTraceLine(
                "\(traceLinePrefix) outcome=results provider=\(result.provider) hits=\(result.results.count)")
            try checkResults()
        case .blocked(let blocked):
            reportTraceLine(
                "\(traceLinePrefix) outcome=blocked providers=\(blocked) correction=\(result.correction ?? "")")
        case .failed(let failure):
            Issue.record(failureComment(failure, result: result), sourceLocation: sourceLocation)
        }
    }

    /// Removes the next step from the end of a correction.
    ///
    /// - Parameter correction: The text of the correction.
    /// - Returns: The correction with no next step and no separator before
    ///   it, or `nil` when the correction does not end with one of
    ///   ``nextSteps``.
    private static func failureText(of correction: String) -> String? {
        nextSteps.map { partSeparator + $0 }
            .first(where: correction.hasSuffix)
            .map { String(correction.dropLast($0.count)) }
    }

    /// Splits the text of a correction with no next step into one part for
    /// each provider, in order.
    ///
    /// - Parameters:
    ///   - failures: The text of the correction, with no next step. See
    ///     ``failureText(of:)``.
    ///   - names: The names of the providers of the search, in order.
    /// - Returns: One part for each name, or `nil` when the text does not
    ///   start with `WebSearchChain.correctionLead` and then name each
    ///   provider in order. The reason of a provider runs to the label of the
    ///   next provider, and the reason of the last provider runs to the end of
    ///   the text.
    private static func failureParts(of failures: String, providers names: [String]) -> [ProviderFailurePart]? {
        let lead = WebSearchChain.correctionLead + partSeparator
        guard failures.hasPrefix(lead), !names.isEmpty else { return nil }
        var rest = Substring(failures.dropFirst(lead.count))
        var parts: [ProviderFailurePart] = []
        for (index, name) in names.enumerated() {
            let label = name + reasonSeparator
            guard rest.hasPrefix(label) else { return nil }
            rest = rest.dropFirst(label.count)
            let nextLabel = names.dropFirst(index + 1).first.map { partSeparator + $0 + reasonSeparator }
            let end = nextLabel.flatMap { rest.range(of: $0)?.lowerBound } ?? rest.endIndex
            parts.append(ProviderFailurePart(provider: name, reason: String(rest[..<end])))
            rest = rest[end...].dropFirst(partSeparator.count)
        }
        return parts
    }

    /// The comment of the failure that the rule records.
    ///
    /// - Parameters:
    ///   - failure: Why the result fails the rule.
    ///   - result: The result of the `search` verb.
    /// - Returns: The cause, then the provider, the hit count, and the
    ///   correction of the result.
    private static func failureComment(_ failure: Failure, result: SearchResult) -> Comment {
        Comment(
            rawValue: """
                the search gave neither results nor a recognized block (\(failure)): \
                provider "\(result.provider)", \(result.results.count) hits, \
                correction: \(result.correction ?? "none")
                """)
    }
}
