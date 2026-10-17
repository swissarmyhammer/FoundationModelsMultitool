import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing
import os

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
/// The engine clock waits on the run clock of the session, and each session
/// here runs on a `ManualRunClock`. A test moves that clock with
/// `ManualRunClock.advance(by:)` only after the timer waits
/// (`ManualRunClock.waitForSleepers(atLeast:orUntil:)`), in a fixed order. No
/// test waits on real time or reads the time that a run took (card `^3np5yzj`:
/// no test checks the speed of the machine).
///
/// Each wait for a step of a run also ends when the run ends
/// (``TerminalDetail/runEnd(of:in:)``). A run that ends before its step thus
/// does not make the test hang: the test fails at once, or its checks of the
/// terminal event fail.
@Suite("runCode ends at its tool-level timeout")
struct RunCodeToolTimeoutTests {
    // MARK: - A run with no progress

    @Test("a mounted runCode that spins with no progress ends as timedOut at the engine clock")
    func spinningSnippetEndsAtTheEngineClock() async throws {
        let clock = ManualRunClock()
        try await withOuterRunContext(runClock: clock) { context in
            let mounted = try Self.mountedRunCode(
                registry: try MultiTool.Builder().buildRegistry(),
                window: Self.stallWindowSeconds,
                on: context
            )

            let rendered = try await Self.callEndingOneWindow(of: clock, on: context) {
                try await mounted.call(arguments: RunCodeArguments(code: "while (true) {}"))
            }

            // The sandbox has no clock to end the loop, thus the outcome comes
            // from the engine clock.
            let terminal = try await Self.terminal(of: rendered, on: context)
            #expect(terminal.outcome == .timedOut)
            #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
        }
    }

    /// ``callEndingOneWindow(of:on:_:)`` ends the window of the run also when
    /// the test throws after the run started.
    ///
    /// The step starts a spinning run, waits until the timer of the run
    /// waits, and then throws. The test then reads the run clock: the window
    /// ended when the clock moved one full window. The order is fixed, thus
    /// the read is the same on each machine. When the window did not end,
    /// the test ends it itself before the close, so that the close never
    /// depends on the cancel of the JavaScriptCore loop.
    @Test("a spinning runCode run ends at the engine clock also when the test throws after the call")
    func aThrowAfterTheCallStillEndsTheWindow() async throws {
        let clock = ManualRunClock()
        try await withOuterRunContext(runClock: clock) { context in
            let mounted = try Self.mountedRunCode(
                registry: try MultiTool.Builder().buildRegistry(),
                window: Self.stallWindowSeconds,
                on: context
            )
            let start = clock.now

            await #expect(throws: InjectedStepFailure.self) {
                try await Self.callEndingOneWindow(of: clock, on: context) { () async throws -> String in
                    let rendered = try await mounted.call(arguments: RunCodeArguments(code: "while (true) {}"))
                    let runEnded = try TerminalDetail.runEnd(of: rendered, in: context)
                    await clock.waitForSleepers(atLeast: Self.timeoutSleepers, orUntil: runEnded)
                    throw InjectedStepFailure()
                }
            }

            let windowEnded = clock.now >= start.advanced(by: .seconds(Self.stallWindowSeconds))
            if !windowEnded {
                clock.advance(by: .seconds(Self.stallWindowSeconds))
            }
            #expect(windowEnded, "the window of the run did not end on the throw path")
        }
    }

    /// The failure of the step of ``aThrowAfterTheCallStillEndsTheWindow()``.
    private struct InjectedStepFailure: Error {}

    @Test("a mounted runCode that awaits a tools.* call that never completes ends as timedOut at the engine clock")
    func pendingToolCallEndsAtTheEngineClock() async throws {
        try await Self.expectGatedCallEndsAtTheEngineClock { registry, context in
            try Self.mountedRunCode(registry: registry, window: Self.stallWindowSeconds, on: context)
        }
    }

    /// The host gives more than the 120 seconds of the clock that inner calls
    /// had before. A small test clock is the outer `runCode` clock. The run
    /// ends with the timeout text of the outer clock, and not with a
    /// `ToolMountError.timedOut` of the inner call.
    @Test("an inner tools.* call under a host config of more than 120 seconds ends at the outer runCode clock")
    func pendingToolCallUnderALongHostConfigEndsAtTheOuterClock() async throws {
        try await Self.expectGatedCallEndsAtTheEngineClock { registry, context in
            try Self.mountedSmallClockRunCode(registry: registry, on: context)
        }
    }

    /// The fetch has no clock of its own, thus only the outer `runCode` clock
    /// can end a fetch whose server never answers. The timeout cancels the
    /// pending inner call, and the cancel stops the request at the stub. The
    /// clock moves only after the request arrived at the stub.
    @Test("a mounted runCode that awaits a tools.web.fetch whose server never answers ends as timedOut at the engine clock")
    func hangingFetchEndsAtTheEngineClock() async throws {
        let stub = WebStub(routes: [Self.hangingPageURL: .hang])
        let web = WebCapability(
            configuration: .keyless, sessionConfiguration: stub.sessionConfiguration, resolver: PublicHostResolver())
        let clock = ManualRunClock()
        try await withOuterRunContext(runClock: clock) { context in
            let mounted = try Self.mountedRunCode(
                registry: try MultiTool.Builder().withCapability(web).buildRegistry(),
                window: Self.stallWindowSeconds,
                on: context
            )

            let snippet = "return await tools.web.fetch({ url: \"\(Self.hangingPageURL)\" });"
            let rendered = try await mounted.call(arguments: RunCodeArguments(code: snippet))
            let runEnded = try TerminalDetail.runEnd(of: rendered, in: context)
            // The event of the stub: the request is in flight. The wait also
            // ends when the run ends, and the test then fails at once.
            try await EventRace.firstOf({ try? await stub.waitForRequest() }, or: runEnded)
            try #require(!stub.requestedURLs.isEmpty, "the run ended before its request reached the stub")
            await Self.endOneWindow(of: clock, orUntil: runEnded)

            let terminal = try await Self.terminal(of: rendered, on: context)
            #expect(terminal.outcome == .timedOut)
            #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
            // The event of the stub: the session stopped the request.
            try await stub.waitForStop()
            #expect(stub.stoppedURLs == [Self.hangingPageURL])
            #expect(stub.requestedURLs == [Self.hangingPageURL])
        }
    }

    // MARK: - A run with progress

    /// The pauses of the snippet fill more than one window. Thus a clock that
    /// progress does not reset ends the run as `.timedOut` at the first
    /// window. Each gap between two progress events is one step of the clock,
    /// far inside the window.
    ///
    /// The order of each turn is fixed: the progress of the turn reaches the
    /// run (the sink of the mount gets it after the run counts it), the pause
    /// of the turn starts, the clock moves one step, the timer waits again
    /// when the step ended a window, and only then the pause ends. Thus the
    /// next progress always comes after the timer started its window.
    @Test("a mounted runCode that calls progress() inside each window is not ended at the first window")
    func progressResetsTheEngineClock() async throws {
        let pause = PacedPauseTool(name: "pause", turns: Self.turnCount)
        let sink = ProgressSignalSink()
        let clock = ManualRunClock()
        try await withOuterRunContext(runClock: clock) { context in
            let mounted = try Self.mountedRunCode(
                registry: try MultiTool.Builder().addTool(pause).buildRegistry(),
                window: Self.progressWindowSeconds,
                on: context,
                postingTo: sink
            )

            let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.progressSnippet))
            // Each wait of a turn also ends when the run ends, and the test then
            // fails at once.
            let runEnded = try TerminalDetail.runEnd(of: rendered, in: context)
            for turn in 0..<Self.turnCount {
                try await EventRace.requireOpen(
                    sink.gate(for: Self.progressDetail(turn: turn)), orFirstOf: runEnded,
                    orFail: "the run ended before the progress of turn \(turn)")
                try await EventRace.requireOpen(
                    pause.hold(turn: turn).arrival, orFirstOf: runEnded,
                    orFail: "the run ended before the pause of turn \(turn)")
                await clock.waitForSleepers(atLeast: Self.timeoutSleepers, orUntil: runEnded)
                clock.advance(by: Self.pauseStep)
                await clock.waitForSleepers(atLeast: Self.timeoutSleepers, orUntil: runEnded)
                pause.hold(turn: turn).release.open()
            }

            let terminal = try await Self.terminal(of: rendered, on: context)
            #expect(terminal.outcome == .succeeded, "terminal was: \(terminal)")
            #expect(terminal.detail == Self.renderedPauseResult)
        }
    }

    // MARK: - Fixtures

    /// The engine window of the tests with no progress, in seconds.
    ///
    /// A run with no progress ends after one window. The clock is a
    /// `ManualRunClock`, thus the value is a number in the timeout text and
    /// no real wait.
    private static let stallWindowSeconds: TimeInterval = 0.3

    /// The configured `executionTimeLimit` of the long host config, in
    /// seconds.
    ///
    /// More than the 120 seconds of the clock that inner calls had before.
    /// The test with this config never moves the clock that far: the small
    /// test clock of ``SmallClockRunCode`` ends the run first.
    private static let longHostWindowSeconds: TimeInterval = 600

    /// The page of the hanging fetch test. Its stub route never answers.
    private static let hangingPageURL = "https://site.example/hang"

    /// The engine window of the progress test, in seconds.
    private static let progressWindowSeconds: TimeInterval = 2

    /// How many pauses of ``progressSnippet`` fill one progress window.
    private static let pausesPerWindow = 10

    /// How many progress windows the pauses of ``progressSnippet`` fill.
    ///
    /// More than one, so that a clock with no reset ends the run.
    private static let windowsOfPauses = 2

    /// How many turns ``progressSnippet`` makes: one progress call and one
    /// pause each.
    private static let turnCount = pausesPerWindow * windowsOfPauses

    /// How far the clock moves while one pause holds: one part of
    /// ``progressWindowSeconds`` in ``pausesPerWindow``.
    private static let pauseStep: Duration = .seconds(progressWindowSeconds / Double(pausesPerWindow))

    /// How many waits the run clock holds while a run is in flight: the
    /// timeout of the run. The settle period of each mount here is `0`, thus
    /// it adds no wait.
    private static let timeoutSleepers = 1

    /// The snippet of the progress test.
    ///
    /// Each turn of the loop calls `progress()` and then awaits one pause.
    /// The snippet returns the result of the last pause.
    private static var progressSnippet: String {
        """
        let last;
        for (let turn = 0; turn < \(turnCount); turn++) {
          progress("turn " + turn);
          last = await tools.pause();
        }
        return last;
        """
    }

    /// The progress detail that ``progressSnippet`` posts in one turn.
    ///
    /// - Parameter turn: The turn, from `0`.
    /// - Returns: The detail.
    private static func progressDetail(turn: Int) -> String {
        "turn \(turn)"
    }

    /// What `ResultRenderer` makes of the value that ``progressSnippet``
    /// returns.
    private static let renderedPauseResult = "\"pause-result\""

    /// Waits until the timer of the run waits on `clock`, and then moves the
    /// clock one full stall window, so that a timer with no progress ends.
    ///
    /// The wait for the timer also ends when `runEnded` returns. A run that
    /// ended before its timer waits thus does not make the test hang: the
    /// clock moves, and the check of the terminal event of the run fails.
    ///
    /// - Parameters:
    ///   - clock: The run clock of the session.
    ///   - runEnded: The wait for the end of the run — see
    ///     ``TerminalDetail/runEnd(of:in:)``.
    private static func endOneWindow(
        of clock: ManualRunClock, orUntil runEnded: @escaping @Sendable () async -> Void
    ) async {
        await clock.waitForSleepers(atLeast: timeoutSleepers, orUntil: runEnded)
        clock.advance(by: .seconds(stallWindowSeconds))
    }

    /// Runs `call`, and then ends one stall window of the run that `call`
    /// started. It ends the window when `call` returns and when `call`
    /// throws.
    ///
    /// A spinning snippet ends only at the engine clock or at a cancel that
    /// stops the JavaScriptCore loop. `close()` waits for each run body to
    /// end. Thus a window that ends on the return path alone makes the close
    /// on the throw path depend on that cancel. Here the clock ends the run
    /// in a fixed order on each path.
    ///
    /// The window ends only when `call` left a new run open. The run plane
    /// lists the run before the call returns or throws. A call that threw
    /// before it started a run leaves no timer, and a wait for that timer
    /// would not end.
    ///
    /// - Parameters:
    ///   - clock: The run clock of the session.
    ///   - context: The session context that tracks the runs.
    ///   - call: The mounted call that starts the run.
    /// - Returns: What `call` returned.
    /// - Throws: What `call` threw.
    private static func callEndingOneWindow(
        of clock: ManualRunClock, on context: ToolContext, _ call: () async throws -> String
    ) async throws -> String {
        let runsBefore = Set(await context.backgroundRuns().map(\.completionToken))
        return try await ensuring({
            let runsAfter = Set(await context.backgroundRuns().map(\.completionToken))
            guard let newRun = runsAfter.subtracting(runsBefore).first else { return }
            await endOneWindow(of: clock, orUntil: { await TerminalDetail.waitForEnd(of: newRun, in: context) })
        }, after: call)
    }

    /// Mounts a `runCode` tool the way a Router session mounts every tool.
    ///
    /// The sandbox of its interpreter has no clock, thus only the engine clock
    /// can end a run.
    ///
    /// - Parameters:
    ///   - registry: The registry that the snippets call into.
    ///   - window: The engine window: the configured `executionTimeLimit`.
    ///   - context: The session context that tracks the runs.
    ///   - sink: The sink that each run of the mount posts to, or `nil` for
    ///     the sinks of the session.
    /// - Returns: The composed, model-facing `runCode`.
    private static func mountedRunCode(
        registry: MultiTool.Registry, window: TimeInterval, on context: ToolContext,
        postingTo sink: (any OperationEventSink)? = nil
    ) throws -> any Tool<RunCodeArguments, String> {
        // A settle period of 0 sends each run to the background at once, so that
        // the terminal event of the run plane holds the outcome of the clock.
        let runCode = MultiTool(
            registry: registry,
            configuration: MultiToolConfiguration(executionTimeLimit: window, inlineSettleGrace: 0),
            interpreter: JSCInterpreter()
        )
        guard let sink else {
            return try #require(context.mount(runCode, as: .synchronous) as? any Tool<RunCodeArguments, String>)
        }
        return try #require(
            context.mount(runCode, as: .synchronous, postingTo: sink) as? any Tool<RunCodeArguments, String>)
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
    /// The clock moves only after the gated call started. The run ends as
    /// `.timedOut` with the timeout text of the outer `runCode` clock.
    /// Nothing releases the gate, thus the timeout cancels the pending inner
    /// call, and the call records that event as it unwinds.
    ///
    /// - Parameter mount: Makes the mounted `runCode` over the registry of the
    ///   gated tool, on the session context.
    private static func expectGatedCallEndsAtTheEngineClock(
        mounting mount: (MultiTool.Registry, ToolContext) throws -> any Tool<RunCodeArguments, String>
    ) async throws {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let clock = ManualRunClock()
        try await withOuterRunContext(runClock: clock) { context in
            let mounted = try mount(try MultiTool.Builder().addTool(gated).buildRegistry(), context)

            let rendered = try await mounted.call(arguments: RunCodeArguments(code: "return await tools.gated();"))
            // The wait for the start also ends when the run ends, and the test
            // then fails at once.
            let runEnded = try TerminalDetail.runEnd(of: rendered, in: context)
            try await gated.requireStart(orUntil: runEnded)
            await endOneWindow(of: clock, orUntil: runEnded)

            let terminal = try await Self.terminal(of: rendered, on: context)
            #expect(terminal.outcome == .timedOut)
            #expect(terminal.detail == Self.timedOutText(window: Self.stallWindowSeconds))
            #expect(!latch.isReleased)
            try await gated.waitUntilCancelled()
        }
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

/// A tool whose calls each wait on a hold of their own, in call order.
///
/// The progress test opens the hold of each turn after it moved the run
/// clock, thus each pause ends at a point that the test chose, and no pause
/// waits on real time.
private final class PacedPauseTool: Tool, Sendable {
    let name: String
    let description = "Waits until the test lets this call go on, then returns a fixed value."

    /// The hold of each call, by call index.
    private let holds: [HeldCall]

    /// The index of the next call.
    private let nextCall = OSAllocatedUnfairLock(initialState: 0)

    /// Creates a tool with one hold for each of `turns` calls.
    ///
    /// - Parameters:
    ///   - name: This tool's `tools.*` name.
    ///   - turns: How many calls get a hold. A later call passes at once.
    init(name: String, turns: Int) {
        self.name = name
        self.holds = (0..<turns).map { _ in HeldCall() }
    }

    /// The hold of one call.
    ///
    /// - Parameter turn: The index of the call, from `0`.
    /// - Returns: The hold.
    func hold(turn: Int) -> HeldCall {
        holds[turn]
    }

    func call(arguments: NoArguments) async throws -> String {
        let index = nextCall.withLock { next -> Int in
            defer { next += 1 }
            return next
        }
        if holds.indices.contains(index) {
            try await holds[index].pass()
        }
        return "\(name)-result"
    }
}

/// A sink that a mount posts each event of its runs to, and that opens one
/// gate for each progress detail it gets.
///
/// `ToolRun.post(event:)` counts a progress event for the timeout of the run
/// before it sends the event to this sink. Thus a test that waits here knows
/// that the run counted the progress.
private final class ProgressSignalSink: OperationEventSink, Sendable {
    /// The gate of each progress detail, made on the first wait or post.
    private let gates = OSAllocatedUnfairLock<[String: TestGate]>(initialState: [:])

    /// Opens the gate of the detail of a progress event.
    ///
    /// - Parameter event: The posted event.
    func post(event: OperationEvent) async {
        guard event.kind == .progress else { return }
        gate(for: event.detail).open()
    }

    /// The gate of one progress detail: it opens when a progress event with
    /// `detail` arrived.
    ///
    /// - Parameter detail: The progress detail.
    /// - Returns: The gate, made when it did not exist.
    func gate(for detail: String) -> TestGate {
        gates.withLock { gates in
            if let gate = gates[detail] {
                return gate
            }
            let gate = TestGate()
            gates[detail] = gate
            return gate
        }
    }
}
