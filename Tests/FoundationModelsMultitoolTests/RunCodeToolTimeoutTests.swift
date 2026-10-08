import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Proves the one outer timeout of a `runCode` call: the engine clock that
/// ``MultiTool/timeout(from:)`` gives and the session mount enforces.
///
/// Each test mounts `MultiTool` the way a Router session mounts it. One test
/// puts ``SmallClockRunCode`` in front of `MultiTool`, so that the outer clock
/// is small and the host config is long. The sandbox of `JSCInterpreter` has
/// no clock, thus only the engine clock can end a run.
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

        // The sandbox has no clock to end the loop, thus the outcome comes
        // from the engine clock.
        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .timedOut)
        #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
    }

    @Test(
        "a mounted runCode that awaits a tools.* call that never completes ends as timedOut at the engine clock",
        .timeLimit(TestHangGuard.timeLimit))
    func pendingToolCallEndsAtTheEngineClock() async throws {
        try await Self.expectGatedCallEndsAtTheEngineClock { registry, context in
            try Self.mountedRunCode(registry: registry, window: Self.stallWindowSeconds, on: context)
        }
    }

    /// The host gives more than the 120 seconds of the clock that inner calls
    /// had before. A small test clock is the outer `runCode` clock, so that
    /// the test stays fast. The run ends with the timeout text of the outer
    /// clock, and not with a `ToolMountError.timedOut` of the inner call.
    @Test(
        "an inner tools.* call under a host config of more than 120 seconds ends at the outer runCode clock",
        .timeLimit(TestHangGuard.timeLimit))
    func pendingToolCallUnderALongHostConfigEndsAtTheOuterClock() async throws {
        try await Self.expectGatedCallEndsAtTheEngineClock { registry, context in
            try Self.mountedSmallClockRunCode(registry: registry, on: context)
        }
    }

    /// The fetch has no clock of its own, thus only the outer `runCode` clock
    /// can end a fetch whose server never answers. The timeout cancels the
    /// pending inner call, and the cancel stops the request at the stub.
    @Test(
        "a mounted runCode that awaits a tools.web.fetch whose server never answers ends as timedOut at the engine clock",
        .timeLimit(TestHangGuard.timeLimit))
    func hangingFetchEndsAtTheEngineClock() async throws {
        let stub = WebStub(routes: [Self.hangingPageURL: .hang])
        let web = WebCapability(
            configuration: .keyless, sessionConfiguration: stub.sessionConfiguration, resolver: PublicHostResolver())
        let context = try await makeOuterRunContext()
        let mounted = try Self.mountedRunCode(
            registry: try MultiTool.Builder().withCapability(web).buildRegistry(),
            window: Self.stallWindowSeconds,
            on: context
        )

        let snippet = "return await tools.web.fetch({ url: \"\(Self.hangingPageURL)\" });"
        let rendered = try await mounted.call(arguments: RunCodeArguments(code: snippet))

        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .timedOut)
        #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
        try await TestPoll.waitUntil("the session stopped the fetch request") {
            stub.stoppedURLs == [Self.hangingPageURL]
        }
        #expect(stub.requestedURLs == [Self.hangingPageURL])
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

    /// The engine window of the tests with no progress, in seconds.
    ///
    /// Small, so that the suite stays fast. A run with no progress ends after
    /// one window.
    private static let stallWindowSeconds: TimeInterval = 0.3

    /// The configured `executionTimeLimit` of the long host config, in
    /// seconds.
    ///
    /// More than the 120 seconds of the clock that inner calls had before.
    /// The test with this config never waits for it: the small test clock of
    /// ``SmallClockRunCode`` ends the run first.
    private static let longHostWindowSeconds: TimeInterval = 600

    /// The page of the hanging fetch test. Its stub route never answers.
    private static let hangingPageURL = "https://site.example/hang"

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
    /// The sandbox of its interpreter has no clock, thus only the engine clock
    /// can end a run.
    ///
    /// - Parameters:
    ///   - registry: The registry that the snippets call into.
    ///   - window: The engine window: the configured `executionTimeLimit`.
    ///   - context: The session context that tracks the runs.
    /// - Returns: The composed, model-facing `runCode`.
    private static func mountedRunCode(
        registry: MultiTool.Registry, window: TimeInterval, on context: ToolContext
    ) throws -> any Tool<RunCodeArguments, String> {
        // A settle period of 0 sends each run to the background at once, so that
        // the terminal event of the run plane holds the outcome of the clock.
        let runCode = MultiTool(
            registry: registry,
            configuration: MultiToolConfiguration(executionTimeLimit: window, inlineSettleGrace: 0),
            interpreter: JSCInterpreter()
        )
        return try #require(context.mount(runCode, as: .synchronous) as? any Tool<RunCodeArguments, String>)
    }

    /// Mounts a ``SmallClockRunCode`` the way a Router session mounts every
    /// tool.
    ///
    /// The wrapped `runCode` has the long host config
    /// (``longHostWindowSeconds``). The small test clock
    /// (``stallWindowSeconds``) is the outer clock of the call.
    ///
    /// - Parameters:
    ///   - registry: The registry that the snippets call into.
    ///   - context: The session context that tracks the runs.
    /// - Returns: The composed, model-facing `runCode`.
    private static func mountedSmallClockRunCode(
        registry: MultiTool.Registry, on context: ToolContext
    ) throws -> any Tool<RunCodeArguments, String> {
        let runCode = SmallClockRunCode(
            wrapped: MultiTool(
                registry: registry,
                configuration: MultiToolConfiguration(executionTimeLimit: longHostWindowSeconds),
                interpreter: JSCInterpreter()
            ),
            window: stallWindowSeconds
        )
        // A settle period of 0 sends each run to the background at once, so that
        // the terminal event of the run plane holds the outcome of the clock.
        return try #require(
            context.settling(within: 0).mount(runCode, as: .synchronous) as? any Tool<RunCodeArguments, String>)
    }

    /// Runs a snippet that awaits a `tools.gated` call that never completes,
    /// and expects the outer clock of ``stallWindowSeconds`` to end the run.
    ///
    /// The run ends as `.timedOut` with the timeout text of the outer
    /// `runCode` clock. Nothing releases the gate, thus the timeout cancels
    /// the pending inner call, and the call records that as it unwinds.
    ///
    /// - Parameter mount: Makes the mounted `runCode` over the registry of the
    ///   gated tool, on the session context.
    private static func expectGatedCallEndsAtTheEngineClock(
        mounting mount: (MultiTool.Registry, ToolContext) throws -> any Tool<RunCodeArguments, String>
    ) async throws {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let context = try await makeOuterRunContext()
        let mounted = try mount(try MultiTool.Builder().addTool(gated).buildRegistry(), context)

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: "return await tools.gated();"))

        let terminal = try await Self.terminal(of: rendered, on: context)
        #expect(terminal.outcome == .timedOut)
        #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
        #expect(!latch.isReleased)
        try await TestPoll.waitUntil("the gated call unwound") { gated.wasCancelled }
    }

    /// Waits for the terminal event of the run that a mounted call started.
    ///
    /// The settle period of the call is 0, thus the call answers with the
    /// pending envelope. The run plane keeps the terminal event of the run.
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

/// A `runCode` with a small test clock in place of the clock of its host
/// config.
///
/// The engine reads the tool-level timeout of `MultiTool` ahead of the clock
/// of the mount. Thus a test that wants a long host config and a short outer
/// clock puts this decorator in front of `MultiTool`. It has the same name,
/// so that the timeout text names `runCode`, and it declares the background
/// mount of `runCode` with ``window`` as the clock. Each call goes to the
/// wrapped `MultiTool` unchanged.
private struct SmallClockRunCode: Tool, BackgroundTool {
    /// The `runCode` that runs each snippet.
    let wrapped: MultiTool

    /// The small test clock: the outer clock of each call, in seconds.
    let window: TimeInterval

    /// The name of the wrapped `runCode`.
    var name: String { wrapped.name }

    /// The description of the wrapped `runCode`.
    var description: String { wrapped.description }

    /// The background mount of `runCode`, with ``window`` as its clock.
    var mount: ToolMount? { ToolMount(mode: .background, timeout: window) }

    /// Runs the snippet on the wrapped `runCode`.
    ///
    /// - Parameter arguments: The snippet to run.
    /// - Returns: The rendered result of the wrapped `runCode`.
    func call(arguments: RunCodeArguments) async throws -> String {
        try await wrapped.call(arguments: arguments)
    }
}
