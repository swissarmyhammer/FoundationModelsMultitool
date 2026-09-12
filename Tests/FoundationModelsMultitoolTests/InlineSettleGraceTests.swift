import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Exercises the wait a `runCode` call makes before it answers: the knob that
/// sets it, the settled envelope a quick snippet comes back in, and the
/// pending envelope a host that turns the wait off still gets.
///
/// The behaviour under test belongs to Router's `BackgroundToolRunner`, and
/// this package owns the two things that drive it: the value in
/// ``MultiToolConfiguration/inlineSettleGrace`` and the sentence in
/// ``MultiTool/resultInstruction(forCompletionToken:)``. So each test here
/// goes through the session mount, which is where the two meet.
@Suite("runCode answers a short snippet with its own result")
struct InlineSettleGraceTests {
    /// The snippet every test runs: one `tools.*` call, over at once.
    private static let quickSnippet = "const r = await tools.getCities({}); return r.cities.length;"

    /// What ``quickSnippet`` returns: the count, and the notice
    /// `ToolReturnLedger` closes the run with, because a count derived from
    /// the names shares no text with them.
    private static var quickSnippetResult: String {
        "3\n\n\(ToolReturnLedger.uncarriedReturnNotice)"
    }

    /// A registry carrying one real tool.
    private static func registry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// Mounts `tool` the way a Router session mounts every tool.
    ///
    /// - Parameters:
    ///   - tool: the tool to mount.
    ///   - context: the session context the mount tracks runs on.
    /// - Returns: the composed, model-facing `runCode`.
    private static func mounted(
        _ tool: MultiTool, on context: ToolContext
    ) throws -> any Tool<RunCodeArguments, String> {
        try #require(context.mount(tool, as: .synchronous) as? any Tool<RunCodeArguments, String>)
    }

    /// Decodes the envelope a mounted call answered with.
    ///
    /// - Parameter rendered: the call's output.
    /// - Returns: the decoded envelope.
    private static func envelope(_ rendered: String) throws -> PendingRunEnvelope {
        #expect(PendingRunEnvelope.isRendered(text: rendered), "answer was: \(rendered)")
        return try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
    }

    // MARK: - The knob

    @Test("the stock wait is two seconds, and a host's own value reaches the tool")
    func configurationCarriesTheWait() throws {
        #expect(MultiToolConfiguration.default.inlineSettleGrace == 2)
        #expect(
            MultiToolConfiguration.default.inlineSettleGrace
                == MultiToolConfiguration.defaultInlineSettleGrace
        )

        let registry = try Self.registry()
        let configured = MultiTool(
            registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 5)
        )

        #expect(configured.inlineSettleGrace == 5)
        #expect(MultiTool(registry: registry).inlineSettleGrace == 2)
    }

    @Test("a negative wait is clamped to no wait at all")
    func negativeWaitIsClamped() {
        #expect(MultiToolConfiguration(inlineSettleGrace: -1).inlineSettleGrace == 0)
    }

    // MARK: - The two envelopes

    @Test("a snippet that finishes inside the wait answers with its own result, and the run plane still holds that result")
    func quickSnippetAnswersWithItsResult() async throws {
        let context = try await makeOuterRunContext()
        let runCode = MultiTool(registry: try Self.registry())
        let mounted = try Self.mounted(runCode, on: context)

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.quickSnippet))

        let envelope = try Self.envelope(rendered)
        #expect(!envelope.pending)
        #expect(envelope.detail == Self.quickSnippetResult)
        #expect(envelope.outcome == "succeeded")
        #expect(
            envelope.next == runCode.resultInstruction(forCompletionToken: envelope.completionToken)
        )

        // The snippet settled by itself, so a model that calls `wait` on the
        // token anyway is answered with the same result.
        let collected = await context.wait(
            completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds
        )
        guard case .settled(let terminal) = collected else {
            Issue.record("the snippet never settled: \(collected)")
            return
        }
        #expect(terminal.detail == Self.quickSnippetResult)
    }

    @Test("the settled sentence sends the model to its own detail, and never to the wait tool")
    func settledSentenceKeepsTheModelAwayFromWait() throws {
        let completionToken = ToolContext.makeCompletionToken()

        let sentence = MultiTool(registry: try Self.registry())
            .resultInstruction(forCompletionToken: completionToken)

        #expect(sentence.contains("detail field"))
        #expect(sentence.contains("Answer from that result now"))
        #expect(sentence.contains("Do not call the wait tool"))
        #expect(sentence.contains(completionToken))
        #expect(sentence.contains("never reply that the result will arrive later"))
    }

    @Test("a host that turns the wait off gets the completion token back, as every mounted call did before")
    func noWaitAnswersWithTheCompletionToken() async throws {
        let context = try await makeOuterRunContext()
        let runCode = MultiTool(
            registry: try Self.registry(),
            configuration: MultiToolConfiguration(inlineSettleGrace: 0)
        )
        let mounted = try Self.mounted(runCode, on: context)

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.quickSnippet))

        let envelope = try Self.envelope(rendered)
        #expect(envelope.pending)
        #expect(envelope.detail == nil)
        #expect(
            envelope.next == runCode.collectInstruction(forCompletionToken: envelope.completionToken)
        )

        let collected = await context.wait(
            completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds
        )
        guard case .settled(let terminal) = collected else {
            Issue.record("the snippet never settled: \(collected)")
            return
        }
        #expect(terminal.detail == Self.quickSnippetResult)
    }
}
