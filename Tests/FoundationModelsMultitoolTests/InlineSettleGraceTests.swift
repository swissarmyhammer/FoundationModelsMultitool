import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Exercises the wait a `runCode` call makes before it answers: the knob that
/// sets it, the own result a quick snippet comes back with, and the pending
/// envelope a host that turns the wait off still gets.
///
/// The behaviour under test belongs to the `BackgroundToolRunner` of
/// FoundationModelsExtras, and this package owns the value that drives it:
/// ``MultiToolConfiguration/inlineSettleGrace``. So each test here goes
/// through the session mount, which is where the two meet.
@Suite("runCode answers a short snippet with its own result", .ownsTemporaryDirectories)
struct InlineSettleGraceTests {
    /// The snippet every test runs: one `tools.*` call, over at once.
    private static let quickSnippet = "const r = await tools.getCities({}); return r.cities.length;"

    /// What ``quickSnippet`` returns: the count, and the notice
    /// `ToolReturnLedger` closes the run with, because a count derived from
    /// the names shares no text with them.
    private static var quickSnippetResult: String {
        "3\n\n\(ToolReturnLedger.uncarriedReturnNotice)"
    }

    /// The wait of the quick snippet in the test that runs it beside a slow
    /// tool, in seconds.
    ///
    /// The wait is on a `ManualRunClock` that the test never advances, thus
    /// the wait never ends by time and the value has no effect on the result
    /// (card `^3np5yzj`: no test checks the speed of the machine). The test
    /// proves the property with an event: the quick snippet answers while the
    /// slow tool still spins.
    private static let besideSlowToolGrace: TimeInterval = 1

    /// A registry carrying one real tool.
    private static func registry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// The context of an outer run on a session whose run clock is a
    /// `ManualRunClock` that no test advances.
    ///
    /// The settle period of each mounted call and the timeout of each run wait
    /// on that clock, thus no wait ends by time. A snippet that settles always
    /// answers inside its settle period, and only a period of `0` gives the
    /// pending envelope. No test here reads real time.
    ///
    /// The helper gives the context to `body`, and closes the session of the
    /// context when `body` returns or throws.
    ///
    /// - Parameter body: The work that uses the context.
    /// - Returns: What `body` returned.
    /// - Throws: Whatever standing up the stub session throws, or what `body`
    ///   threw.
    private static func withContextOnStoppedClock<Result>(
        _ body: (ToolContext) async throws -> Result
    ) async throws -> Result {
        try await withOuterRunContext(runClock: ManualRunClock(), body)
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

    @Test("the stock wait is the one hosting default, and a host's own value reaches the tool")
    func configurationCarriesTheWait() throws {
        #expect(MultiToolConfiguration.default.inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
        #expect(MultiToolConfiguration().inlineSettleGrace == ToolMount.defaultInlineSettleGrace)

        let registry = try Self.registry()
        let configured = MultiTool(
            registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 12)
        )

        #expect(configured.inlineSettleGrace == 12)
        #expect(MultiTool(registry: registry).inlineSettleGrace == ToolMount.defaultInlineSettleGrace)
    }

    @Test("a negative wait is clamped to no wait at all")
    func negativeWaitIsClamped() {
        #expect(MultiToolConfiguration(inlineSettleGrace: -1).inlineSettleGrace == 0)
    }

    // MARK: - The own result and the pending envelope

    @Test("a snippet that finishes inside the wait answers with its own result, with no envelope")
    func quickSnippetAnswersWithItsResult() async throws {
        try await Self.withContextOnStoppedClock { context in
            let runCode = MultiTool(registry: try Self.registry())
            let mounted = try Self.mounted(runCode, on: context)

            let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.quickSnippet))

            #expect(rendered == Self.quickSnippetResult)
            #expect(!PendingRunEnvelope.isRendered(text: rendered))
        }
    }

    /// The slow snippet runs on a mount with no wait, thus its call answers
    /// pending at once and the tool goes on in the background. The quick
    /// snippet runs on a second mount whose wait is on a stopped clock. The
    /// test checks an event, not a time: the quick snippet answered with its
    /// own result while the slow tool still kept every CPU busy. A quick
    /// snippet that cannot start until the slow tool stops answers only after
    /// the spin ended, and the last check fails.
    @Test("a snippet that awaits nothing answers with its own result while a slow tool keeps every CPU busy")
    func quickSnippetAnswersBesideABusySlowTool() async throws {
        let latch = ToolReleaseLatch()
        defer { latch.release() }
        let hog = CooperativePoolHogTool(latch: latch)
        try await Self.withContextOnStoppedClock { context in
            try await Self.withContextOnStoppedClock { quickContext in
                let registry = try MultiTool.Builder().addTool(hog).buildRegistry()
                let slowMount = try Self.mounted(
                    MultiTool(registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 0)), on: context)
                let quickMount = try Self.mounted(
                    MultiTool(
                        registry: registry,
                        configuration: MultiToolConfiguration(inlineSettleGrace: Self.besideSlowToolGrace)),
                    on: quickContext
                )
                let slow = try Self.envelope(
                    try await slowMount.call(arguments: RunCodeArguments(code: "return await tools.hog();"))
                )
                #expect(slow.pending)
                // The event of the slow tool: a child started to spin. The wait
                // also ends when the slow snippet ends, and the test then fails
                // at once.
                try await EventRace.firstOf(
                    { try? await hog.waitUntilStarted() },
                    or: { await TerminalDetail.waitForEnd(of: slow.completionToken, in: context) })
                try #require(hog.hasStarted, "the slow snippet ended before the slow tool started to spin")

                let quick = try await quickMount.call(arguments: RunCodeArguments(code: "return \"x\";"))

                #expect(quick == "\"x\"")
                #expect(hog.isSpinning, "the quick snippet answered only after the slow tool stopped")
                latch.release()
                // The spin stops with the latch, and the slow snippet settles.
                let settled = await context.wait(
                    completionToken: slow.completionToken, seconds: scriptedRunSettlementSeconds)
                if case .settled = settled {} else {
                    Issue.record("the slow snippet never settled: \(settled)")
                }
            }
        }
    }

    @Test("a runCode call is described by runCode and the first line of its snippet")
    func aRunCodeCallIsDescribedByItsSnippet() throws {
        let runCode = MultiTool(registry: try Self.registry())

        let description = runCode.callDescription(
            for: RunCodeArguments(code: "\n// read\n" + Self.quickSnippet).generatedContent)

        #expect(description == "runCode // read")
    }

    @Test("a host that turns the wait off gets the completion token back, as every mounted call did before")
    func noWaitAnswersWithTheCompletionToken() async throws {
        try await Self.withContextOnStoppedClock { context in
            let runCode = MultiTool(
                registry: try Self.registry(),
                configuration: MultiToolConfiguration(inlineSettleGrace: 0)
            )
            let mounted = try Self.mounted(runCode, on: context)

            let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.quickSnippet))

            let envelope = try Self.envelope(rendered)
            #expect(envelope.pending)
            #expect(
                envelope.next
                    == PendingRunEnvelope.defaultCollectInstruction(
                        forCompletionToken: envelope.completionToken,
                        describing: CallDescription.of(verb: runCode.name, text: Self.quickSnippet))
            )

            let terminal = try await TerminalDetail.settledEvent(of: envelope.completionToken, in: context)
            #expect(terminal.detail == Self.quickSnippetResult)
        }
    }
}
