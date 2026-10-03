import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Proves the one outer timeout of a `runCode` call: the engine clock that
/// ``MultiTool/timeout(from:)`` gives and the session mount enforces.
///
/// Each test mounts `MultiTool` the way a Router session mounts it, and
/// injects an interpreter whose watchdog is held
/// (`JSCInterpreter.makeWithHeldWatchdog`). Thus the sandbox clock cannot end
/// a run, and only the engine clock can. The tests stay correct when the
/// sandbox deadline is removed.
///
/// The engine clock sleeps on real time, thus a test waits for it. No test
/// reads the time that a run took (card `^3np5yzj`: no test checks the speed
/// of the machine). `TestPoll` and ``TestHangGuard`` are only the bound of a
/// hang.
@Suite("runCode ends at its tool-level timeout")
struct RunCodeToolTimeoutTests {
    // MARK: - A run with no progress

    @Test(
        "a mounted runCode that spins with no progress ends as timedOut at the engine clock",
        .timeLimit(TestHangGuard.timeLimit))
    func spinningSnippetEndsAtTheEngineClock() async throws {
        let context = try await makeOuterRunContext()
        let mounted = try Self.mountedRunCode(
            registry: try MultiTool.Builder().buildRegistry(),
            window: Self.stallWindowSeconds,
            on: context
        )

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: "while (true) {}"))

        // The held watchdog cannot end the loop, thus the outcome comes from
        // the engine clock.
        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .timedOut)
        #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
    }

    @Test(
        "a mounted runCode that awaits a tools.* call that never completes ends as timedOut at the engine clock",
        .timeLimit(TestHangGuard.timeLimit))
    func pendingToolCallEndsAtTheEngineClock() async throws {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let context = try await makeOuterRunContext()
        let mounted = try Self.mountedRunCode(
            registry: try MultiTool.Builder().addTool(gated).buildRegistry(),
            window: Self.stallWindowSeconds,
            on: context
        )

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: "return await tools.gated();"))

        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .timedOut)
        #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
        // Nothing released the gate. The timeout cancelled the pending call,
        // and the call records that as it unwinds.
        #expect(!latch.isReleased)
        try await TestPoll.waitUntil("the gated call unwound") { gated.wasCancelled }
    }

    // MARK: - A run with progress

    /// The pauses of the snippet fill more than one window, and a sleep is a
    /// minimum. Thus the run is alive after the first window, and a clock that
    /// progress does not reset ends it there as `.timedOut`. Each gap between
    /// two progress events is one short pause, far inside the window.
    @Test(
        "a mounted runCode that calls progress() inside each window is not ended at the first window",
        .timeLimit(TestHangGuard.timeLimit))
    func progressResetsTheEngineClock() async throws {
        let pause = WindowRecordingTool(name: "pause", delayNanoseconds: Self.pauseNanoseconds)
        let context = try await makeOuterRunContext()
        let mounted = try Self.mountedRunCode(
            registry: try MultiTool.Builder().addTool(pause).buildRegistry(),
            window: Self.progressWindowSeconds,
            on: context
        )

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.progressSnippet))

        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .succeeded, "terminal was: \(terminal)")
        #expect(terminal.detail == Self.renderedPauseResult)
    }

    // MARK: - Fixtures

    /// The engine window of the two tests with no progress, in seconds.
    ///
    /// Small, so that the suite stays fast. A run with no progress ends after
    /// one window.
    private static let stallWindowSeconds: TimeInterval = 0.3

    /// The engine window of the progress test, in seconds.
    ///
    /// Larger than ``stallWindowSeconds``, so that one pause stays far inside
    /// the window on a loaded machine.
    private static let progressWindowSeconds: TimeInterval = 2

    /// How many pauses of ``progressSnippet`` fill one progress window.
    private static let pausesPerWindow = 10

    /// How many progress windows the pauses of ``progressSnippet`` fill.
    ///
    /// More than one, so that a clock with no reset ends the run.
    private static let windowsOfPauses = 2

    /// The number of nanoseconds in one second.
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// How long one pause of ``progressSnippet`` sleeps, in nanoseconds: one
    /// part of ``progressWindowSeconds`` in ``pausesPerWindow``.
    private static var pauseNanoseconds: UInt64 {
        UInt64(progressWindowSeconds / TimeInterval(pausesPerWindow) * nanosecondsPerSecond)
    }

    /// The snippet of the progress test.
    ///
    /// Each turn of the loop calls `progress()` and then awaits one pause.
    /// The snippet returns the result of the last pause.
    private static var progressSnippet: String {
        """
        let last;
        for (let turn = 0; turn < \(pausesPerWindow * windowsOfPauses); turn++) {
          progress("turn " + turn);
          last = await tools.pause();
        }
        return last;
        """
    }

    /// What `ResultRenderer` makes of the value that ``progressSnippet``
    /// returns.
    private static let renderedPauseResult = "\"pause-result\""

    /// Mounts a `runCode` tool the way a Router session mounts every tool.
    ///
    /// The watchdog of its interpreter is held, thus only the engine clock can
    /// end a run.
    ///
    /// - Parameters:
    ///   - registry: The registry that the snippets call into.
    ///   - window: The engine window: the configured `executionTimeLimit`.
    ///   - context: The session context that tracks the runs.
    /// - Returns: The composed, model-facing `runCode`.
    private static func mountedRunCode(
        registry: MultiTool.Registry, window: TimeInterval, on context: ToolContext
    ) throws -> any Tool<RunCodeArguments, String> {
        let runCode = MultiTool(
            registry: registry,
            configuration: MultiToolConfiguration(executionTimeLimit: window),
            interpreter: JSCInterpreter.makeWithHeldWatchdog()
        )
        return try #require(context.mount(runCode, as: .synchronous) as? any Tool<RunCodeArguments, String>)
    }

    /// Waits for the terminal event of the run that a mounted call started.
    ///
    /// The call answers with the settled envelope or with the pending
    /// envelope. The run plane keeps the terminal event in both cases.
    ///
    /// - Parameters:
    ///   - rendered: The output of the mounted call.
    ///   - context: The session context that tracks the run.
    /// - Returns: The terminal event of the run.
    private static func terminal(of rendered: String, on context: ToolContext) async throws -> OperationEvent {
        let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        return try await TerminalDetail.settledEvent(of: envelope.completionToken, in: context)
    }

    /// The text of the engine timeout for a `runCode` run.
    ///
    /// - Parameter window: The engine window.
    /// - Returns: The text "runCode timed out after … seconds with no
    ///   progress".
    private static func timedOutText(window: TimeInterval) -> String {
        ToolMountError.timedOut(tool: runCodeToolName, timeoutSeconds: window).description
    }

    /// The tool name that the timeout text names: the model-facing name of
    /// `MultiTool`.
    private static let runCodeToolName = "runCode"
}
