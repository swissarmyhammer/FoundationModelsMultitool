import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import MCP
import MCPTestServer
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for `MCPServer.call(name:arguments:)` on the run plane of
/// Router: the five acceptance criteria of the call rewrite, the two in-band
/// answers of the call path, and the progress cases of the sibling's
/// `OperationEventsTests` adapted to the ambient context.
///
/// Ported in part from
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/OperationEventsTests.swift`.
/// The sibling drove each call through an `MCPTool` connected to a sink and
/// forked per session; here the call is a plain `Tool` (``MCPCallProbeTool``)
/// the shared engine of Router mounts, and the events reach the sink the
/// engine was given. The progress cases that are here:
///
/// - `progressThenExactlyOneCompleted`
/// - `concurrentCallsAreDistinguishableByCorrelationID`
///
/// The cases of the source that are not here, and why:
///
/// - `chattyServerThrottlesProgressEvents` — the throttle case. The server
///   keeps no throttle: every progress notification reaches
///   `ToolContext.progress`, and the engine's clock is what progress resets.
/// - `forksSeeOnlyTheirOwnCallsViaListCalls`,
///   `handleFromOneForkIsNotFoundThroughAnother`,
///   `toolsWithinOneForkAgreeOnScope`,
///   `unconnectedDirectServerCallStillObservesItsOwnCalls` — the detach and
///   follow-up-tool cases. A call never detaches, and the builtins of the
///   run plane replaced the follow-up tools.
/// - `successfulCallPostsSuccessOutcome`, `isErrorResultPostsIsErrorOutcome`,
///   `timedOutCallPostsTimedOutOutcome`, `cancelledCallPostsCancelledOutcome`
///   — the terminal outcomes the engine of Router owns; `ToolRun` maps them,
///   and the cancellation case stands here in its wire-level shape.
/// - `twoConnectingCopiesDoNotStealEachOthersEvents`,
///   `connectingIsPureAndReceiverIsUnchanged`,
///   `lateConnectingDoesNotRedirectAnInFlightCall`,
///   `forkedSharesConnectionWithoutReconnectingOrRelisting` — the
///   `connecting(_:)` and `forked()` cases of the sibling's `MCPTool`, which
///   the `MCPTool` of this package does not carry.
///
/// Each test binds a real `ToolContext` from a stub session around the call, the
/// way `ShellExecuteTests` does, and the `.lost` settlement case runs the call
/// inside a mounted `MultiTool` over that session's own run plane.
@Suite("MCPServerCallTests")
struct MCPServerCallTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with.
    private static let serverName = "call-test-server"

    /// The text the echo case sends and expects back.
    private static let echoText = "hi"

    /// The name of the progress-reporting tool of the progress cases.
    private static let progressToolName = "slow"

    /// How many progress notifications the short progress tool sends.
    private static let progressSteps = 3

    /// The name of the tool whose call holds on the server until the test
    /// releases it, thus the call is still in flight when the test acts on
    /// it.
    private static let heldToolName = "held"

    /// How many recorded notifications the cancel cases wait for.
    private static let oneNotification = 1

    /// The name of the tool that drops the transport mid-call.
    private static let droppingToolName = "drops"

    /// The name of the tool that answers an `isError` result.
    private static let failingToolName = "fails"

    /// The text the failing tool answers.
    private static let failingToolText = "nope"

    /// The bound of the bare call of the timeout cases. The test clock
    /// records it and ends it; no real time passes.
    private static let bareCallTimeout = Duration.milliseconds(50)

    /// How many sleeps the timer of one bare call asks the clock for.
    private static let oneBareTimerSleep = 1

    /// The name of the tool that never answers and ignores cancellation.
    private static let hangingToolName = "hangs"

    /// The inner-call bound of the context case, in seconds. The run clock of
    /// the test is a `ManualRunClock`, and the test moves it by this bound.
    /// Thus no real time passes, and the value is only a number.
    private static let innerCallBoundSeconds: TimeInterval = 0.05

    /// How many sleepers the inner-call bound puts on the run clock: the one
    /// timer of the mount.
    private static let innerCallBoundSleepers = 1

    /// The inner-call mount of the context case: the run-to-completion mode
    /// of `RunBinding.innerCallMount`, with an engine clock of its own.
    /// `RunBinding.innerCallMount` states no clock, because the outer
    /// `runCode` clock bounds an inner call. This test has no outer `runCode`,
    /// thus it injects this mount to put an engine clock over the MCP call.
    private static let shortInnerCallMount = ToolMount(
        mode: .runToCompletion, timeout: innerCallBoundSeconds)

    /// How many terminal events one run posts.
    private static let terminalEventCount = 1

    /// How many concurrent calls the correlation case makes.
    private static let concurrentCallCount = 2

    /// The `runCode` snippet that awaits the probe and returns its answer.
    private static let probeSnippet = "return await tools.\(MCPCallProbeTool.probeName)();"

    // MARK: - Helpers

    /// A scripted server that serves `tools`, connected to a fresh
    /// `MCPServer` named ``serverName`` over the in-memory transport — the
    /// shared ``MCPTestSupport/connectedMCPServer(serving:name:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:)``
    /// under this suite's own name.
    ///
    /// - Parameters:
    ///   - tools: The tools to register before the connect.
    ///   - callTimeout: The bound of a bare call of the server.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on.
    ///     Defaults to a `GatedClock` that no test opens.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        serving tools: [ScriptedTool], callTimeout: Duration = MCPServer.defaultCallTimeout,
        callTimeoutClock: any Clock<Duration> = GatedClock()
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedMCPServer(
            serving: tools, name: serverName, callTimeoutClock: callTimeoutClock, callTimeout: callTimeout)
    }

    /// The event that came first in the race of
    /// ``aBareCallTimesOutOnlyOnTheInjectedClock()``.
    private enum BareCallFirstEvent: Equatable {
        /// The timer of the bare call asked the injected clock for its sleep.
        case timerSlept

        /// The bare call ended.
        case callEnded
    }

    /// A scripted tool that answers an `isError` result at once.
    private static var failingTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: failingToolName, description: "Answers an isError result.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            CallTool.Result(
                content: [.text(text: failingToolText, annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    /// A scripted tool that never answers, and does not respond to
    /// cancellation — the hang of ``HangingTransport``, on the server side of
    /// a connected transport. The handler opens `arrival` first, thus a test
    /// knows when the request reached the server.
    ///
    /// - Parameter arrival: The gate the handler opens when it runs.
    /// - Returns: The scripted tool.
    private static func hangingTool(arrival: TestGate) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: hangingToolName, description: "Never answers.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            arrival.open()
            await HangingTransport.hangForever()
        }
    }

    /// The progress-reporting tool of the short progress cases.
    ///
    /// - Parameter scripted: The server to register it on.
    private static func addProgressTool(to scripted: ScriptedServer) async {
        await scripted.addProgressReportingTool(
            named: progressToolName, totalSteps: progressSteps)
    }

    /// Runs one call of `server` under a bound ambient context, the way the
    /// background engine binds one around every mounted call.
    ///
    /// - Parameters:
    ///   - server: The server to call.
    ///   - tool: The name of the tool to call.
    ///   - arguments: The arguments of the call.
    ///   - context: The ambient context to bind.
    /// - Returns: The server's result.
    /// - Throws: What the call throws.
    private static func call(
        _ server: MCPServer, tool: String, arguments: [String: Value]? = nil,
        under context: ToolContext
    ) async throws -> CallTool.Result {
        try await ToolContext.$current.withValue(context) {
            try await server.call(name: tool, arguments: arguments)
        }
    }

    /// A probe of `server` over `tool`, with no arguments.
    private static func probe(_ server: MCPServer, tool: String) -> MCPCallProbeTool {
        MCPCallProbeTool(server: server, toolName: tool, callArguments: nil)
    }

    /// Starts `call`, waits until it arrived at `held`, and fails the test
    /// at once when the call ended first — see
    /// ``EventRace/watch(_:untilArrivalAt:orFail:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - held: The held tool that the call arrives at.
    ///   - call: The call of `held`.
    /// - Returns: The started call.
    /// - Throws: When the call ended before it arrived, or when the task is
    ///   cancelled first.
    private static func watchHeldCall<Success: Sendable>(
        on held: HeldScriptedTool, _ call: @escaping @Sendable () async throws -> Success
    ) async throws -> EventRace.Watched<Success> {
        try await EventRace.watch(
            call, untilArrivalAt: held, orFail: "the call ended before it arrived at the server")
    }

    /// Disconnects `server`, reads the notifications that `scripted`
    /// recorded, and records a failure unless the first one is the
    /// `notifications/cancelled` of the call — see
    /// ``MCPTestSupport/notifications(recordedBy:afterDisconnectOf:count:)``.
    ///
    /// - Parameters:
    ///   - scripted: The server that records the notifications.
    ///   - server: The connected server whose call was cancelled.
    private static func expectOneCancelledNotification(
        recordedBy scripted: ScriptedServer, afterDisconnectOf server: MCPServer
    ) async {
        let recorded = await MCPTestSupport.notifications(
            recordedBy: scripted, afterDisconnectOf: server, count: oneNotification)
        #expect(recorded.first?.method == CancelledNotification.name)
    }

    // MARK: - The result

    @Test("a call against ScriptedServer returns the server's result")
    func aCallReturnsTheServersResult() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        try await MCPTestSupport.withConnection(of: server) {
            try await withOuterRunContext { context in
                let result = try await Self.call(
                    server, tool: ScriptedServer.echoToolName,
                    arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)],
                    under: context)

                #expect(result.isError != true)
                #expect(result.content == [.text(text: Self.echoText, annotations: nil, _meta: nil)])
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// The card's contract: a result with `isError: true` returns as a value,
    /// and the renderer keeps it in band.
    @Test("a result with isError returns as a value")
    func anIsErrorResultReturnsAsAValue() async throws {
        let (scripted, server) = try await Self.connected(serving: [Self.failingTool])
        try await MCPTestSupport.withConnection(of: server) {
            try await withOuterRunContext { context in
                let result = try await Self.call(server, tool: Self.failingToolName, under: context)

                #expect(result.isError == true)
                #expect(result.content == [.text(text: Self.failingToolText, annotations: nil, _meta: nil)])
            }
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Progress

    @Test("a progress notification during a call reaches ToolContext.progress with the run's correlationID")
    func progressReachesTheAmbientContext() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        try await MCPTestSupport.withConnection(of: server) {
            await Self.addProgressTool(to: scripted)
            // `settledOperationEvents(of:ofKind:)` closes the session before it
            // reads. The scope also closes the session when the call throws.
            try await withStubRun { run in
                let context = run.context

                _ = try await Self.call(server, tool: Self.progressToolName, under: context)

                let progressEvents = await settledOperationEvents(of: run, ofKind: .progress)
                #expect(progressEvents.count == Self.progressSteps, "progress events were: \(progressEvents)")
                #expect(progressEvents.allSatisfy { $0.correlationID == context.completionToken })
            }
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Cancellation

    /// The call holds on the server until the test releases it, thus the
    /// cancel always comes while the call is in flight.
    @Test("cancellation of the calling Task sends notifications/cancelled and the call throws CancellationError")
    func cancellationSendsTheNotificationAndThrows() async throws {
        let held = HeldScriptedTool(named: Self.heldToolName)
        let (scripted, server) = try await Self.connected(serving: [held.scriptedTool])
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await held.release() }) {
                try await withOuterRunContext { context in
                    let callTask = try await Self.watchHeldCall(on: held) {
                        try await Self.call(server, tool: Self.heldToolName, under: context)
                    }.task
                    callTask.cancel()

                    await #expect(throws: CancellationError.self) {
                        _ = try await callTask.value
                    }
                    await Self.expectOneCancelledNotification(recordedBy: scripted, afterDisconnectOf: server)
                }
            }
        }
    }

    // MARK: - The transport drop

    @Test("a transport drop mid-call throws MCPServerError.lost, and that value is a LostRunError")
    func aTransportDropMidCallThrowsLost() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        try await MCPTestSupport.withConnection(of: server) {
            await scripted.addTransportDroppingTool(named: Self.droppingToolName)
            try await withOuterRunContext { context in
                let thrown = await MCPCallProbe.thrownError {
                    _ = try await Self.call(server, tool: Self.droppingToolName, under: context)
                }

                guard case .lost? = thrown as? MCPServerError else {
                    Issue.record("expected MCPServerError.lost, got \(String(describing: thrown))")
                    return
                }
                #expect(thrown is any LostRunError)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// eventplan.md § "Phases", the phase-4 note: "A transport drop under an
    /// in-flight request throws a `LostRunError` (Router), and the engine
    /// settles the calling run as `.lost`."
    @Test("a background runCode run whose snippet awaits the call across a transport drop settles as lost")
    func aBackgroundRunAcrossATransportDropSettlesAsLost() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        try await MCPTestSupport.withConnection(of: server) {
            await scripted.addTransportDroppingTool(named: Self.droppingToolName)
            let registry = try MultiTool.Builder()
                .addTool(Self.probe(server, tool: Self.droppingToolName))
                .buildRegistry()
            try await withOuterRunContext { context in
                // A settle period of 0 sends the run to the background at once, so that
                // the drop settles a background run and not the call itself.
                let runCode = MultiTool(registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 0))
                let mounted = try #require(
                    context.mount(runCode, as: .synchronous)
                        as? any FoundationModels.Tool<RunCodeArguments, String>
                )

                let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.probeSnippet))

                #expect(PendingRunEnvelope.isRendered(text: rendered), "answer was: \(rendered)")
                let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
                let settlement = await context.wait(
                    completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds)
                guard case .settled(let terminal) = settlement else {
                    Issue.record("the background run never settled: \(settlement)")
                    return
                }
                #expect(terminal.outcome == .lost, "terminal was: \(terminal)")
            }
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The in-band answers of the call path

    /// A server that is not `.ready` cannot carry a request, and the call
    /// answers in band: the model reads why, and the engine reports the run
    /// as it reports any answered call.
    @Test("a call on a server that is not ready answers an isError result in band")
    func aCallOnAServerThatIsNotReadyAnswersInBand() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        try await MCPTestSupport.withConnection(of: server) {
            try await withOuterRunContext { context in
                await server.disconnect()

                let result = try await Self.call(server, tool: ScriptedServer.echoToolName, under: context)

                #expect(result.isError == true)
                #expect(
                    ToolContentRenderer.render(result: result, budget: RenderBudget.default)
                        .contains(Self.serverName))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// A call with no ambient context has no engine to bound it, so the
    /// server's own `callTimeout` does: the request is cancelled on the wire,
    /// and the call answers in band. The tool holds the call until the test
    /// releases it, thus only the `callTimeout` can end the call. The timer
    /// sleeps on a `ManualClock`, which ends the sleep at once and records
    /// the bound it was asked for.
    @Test("a call with no ambient context is bounded by callTimeout and answers in band")
    func aBareCallIsBoundedByTheCallTimeout() async throws {
        let held = HeldScriptedTool(named: Self.heldToolName)
        let clock = ManualClock()
        let (scripted, server) = try await Self.connected(
            serving: [held.scriptedTool], callTimeout: Self.bareCallTimeout, callTimeoutClock: clock)
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await held.release() }) {
                let result = try await server.call(name: Self.heldToolName, arguments: nil)

                #expect(result.isError == true)
                #expect(clock.recordedSleeps == [Self.bareCallTimeout])
                let recorded = await scripted.waitForRecordedNotifications(count: Self.oneNotification)
                #expect(recorded.first?.method == CancelledNotification.name)
            }
        }
    }

    /// The timer of a bare call sleeps on the clock that the server got at
    /// init, and on no other clock. The clock of this test opens only when
    /// the test opens it, and the tool holds the call. Thus the timer must
    /// ask this clock for its sleep before the call can end, and the call
    /// ends with the timeout result only after the test opens the clock.
    ///
    /// The test races the two events. A timer that sleeps on the real clock
    /// never asks this clock for a sleep, and ends the call first: the race
    /// then records `callEnded`, and the test fails.
    @Test("a bare call stays pending until the injected clock ends its timer, then answers the timeout result")
    func aBareCallTimesOutOnlyOnTheInjectedClock() async throws {
        let held = HeldScriptedTool(named: Self.heldToolName)
        let clock = GatedClock()
        let (scripted, server) = try await Self.connected(
            serving: [held.scriptedTool], callTimeout: Self.bareCallTimeout, callTimeoutClock: clock)
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await held.release() }) {
                let call = try await Self.watchHeldCall(on: held) {
                    try await server.call(name: Self.heldToolName, arguments: nil)
                }
                let callEnded = call.ended

                let first = try await withThrowingTaskGroup(of: BareCallFirstEvent.self) { group in
                    group.addTask {
                        try await clock.waitForRecordedSleeps(atLeast: Self.oneBareTimerSleep)
                        return .timerSlept
                    }
                    group.addTask {
                        try await callEnded.wait()
                        return .callEnded
                    }
                    let winner = try await group.next()
                    group.cancelAll()
                    return winner
                }

                #expect(first == .timerSlept)
                #expect(clock.recordedSleeps == [Self.bareCallTimeout])
                #expect(!callEnded.isOpen)
                clock.open()
                let result = try await call.task.value
                #expect(result.isError == true)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    /// The file header of `MCPServer+Call.swift`: "the engine's clock ... is
    /// what bounds every call made under a context". An inner `tools.*` call
    /// goes through `RunBinding.invoke(_:arguments:journalOp:)`. In a real run
    /// the outer `runCode` clock is that engine clock. This test calls the
    /// binding with no outer `runCode`, thus it injects a mount with a clock
    /// of its own (``shortInnerCallMount``). The server makes no progress, so
    /// only that clock can end the call: it throws the timeout error of the
    /// mount, and the MCP call itself ends with `notifications/cancelled` on
    /// the wire and no entry left in flight.
    ///
    /// The timer of the mount waits on the run clock of the context. Here
    /// that clock is a `ManualRunClock`, and the order is fixed: the test
    /// waits until the request reached the server and the timer sleeps on
    /// the clock, checks that the call did not end, and then moves the clock
    /// by exactly the bound. No real time passes.
    ///
    /// The clock moves only after the arrival. A bound that fires before the
    /// call put its request in flight cancels a call that sent nothing, thus
    /// no `notifications/cancelled` goes out, and a wait for one never ends.
    ///
    /// Each wait of this test is for an event that the test made occur first:
    ///
    /// - The arrival: the test started the call, the clock does not move
    ///   until the test moves it, and the server serves the tool. Thus the
    ///   request reaches the handler, and the handler opens the gate first.
    /// - The sleeper: the mount started its timer with the call, and the
    ///   timer sleeps on this clock until the clock moves.
    /// - The end of the call: the move of the clock ends the sleep of the
    ///   timer, and the mount then cancels the call and returns at once.
    /// - The notification: the request arrived, thus the call put it in
    ///   flight and installed its cancel handler before it sent it. The
    ///   cancel of the mount runs that handler, and the handler starts the
    ///   notice: it ends the entry of the call, and then sends
    ///   `notifications/cancelled` to the server.
    ///
    /// The arrival and the sleeper waits also end when the call ends. The
    /// test then fails at once, and does not hang. The test waits for the
    /// end of each notice before it reads the table of calls in flight, and
    /// the wait for the notification also ends when the transport closed.
    @Test("a call under a context to a server that makes no progress ends at the inner-call bound")
    func aCallUnderAContextEndsAtTheInnerCallBound() async throws {
        let arrival = TestGate()
        let (scripted, server) = try await Self.connected(serving: [Self.hangingTool(arrival: arrival)])
        let clock = ManualRunClock()
        try await MCPTestSupport.withConnection(of: server) {
            try await withOuterRunContext(runClock: clock) { context in
                let binding = RunBinding(context: context, innerMount: Self.shortInnerCallMount)
                let sleepersBefore = clock.sleeperCount

                let invoke = try await EventRace.watch(
                    {
                        await MCPCallProbe.thrownError {
                            _ = try await binding.invoke(
                                Self.probe(server, tool: Self.hangingToolName), arguments: NoArguments())
                        }
                    },
                    untilOpen: arrival, orFail: "the call ended before it reached the server")
                await clock.waitForSleepers(
                    atLeast: sleepersBefore + Self.innerCallBoundSleepers, orUntil: { await invoke.waitForEnd() })
                #expect(!invoke.ended.isOpen)
                clock.advance(by: .seconds(Self.innerCallBoundSeconds))
                let thrown = try await invoke.task.value

                // The hanging tool never answers, thus a call that ended at all was
                // ended by a bound, and the error names the bound that fired: the
                // configured inner-call bound. The test replaces the old check of the
                // real elapsed time (`elapsed >= bound`) with events: the call did
                // not end while the timer slept, and it ended only after the run
                // clock moved by exactly the bound. That is the same fact, and it
                // reads no real time (card `^tm4x2hp`: no test checks the speed of
                // the machine).
                #expect(
                    thrown as? ToolMountError
                        == .timedOut(tool: MCPCallProbeTool.probeName, timeoutSeconds: Self.innerCallBoundSeconds),
                    "thrown was: \(String(describing: thrown))")
                // The cancel of the mount started the notice before the call
                // returned. When the notice ended, the call left the table.
                await server.cancellationNotices.drain()
                #expect(await server.inFlightCalls.isEmpty)
                await Self.expectOneCancelledNotification(recordedBy: scripted, afterDisconnectOf: server)
            }
        }
    }

    // MARK: - The progress cases of OperationEventsTests

    /// The engine posts every progress event before the one terminal event,
    /// and the terminal event carries the outcome.
    ///
    /// The test reads the sink of the mounted run itself. The mounting run
    /// does not show the terminal event of a mounted run as a terminal: it
    /// gets that event as one more `.progress` event.
    @Test("a mounted call posts its progress events then exactly one completed, in that order")
    func progressThenExactlyOneCompleted() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        try await MCPTestSupport.withConnection(of: server) {
            await Self.addProgressTool(to: scripted)
            let sink = RecordingEventSink()
            try await withOuterRunContext { context in
                let engine = MCPCallProbe.mountedRunToCompletion(
                    Self.probe(server, tool: Self.progressToolName), on: context,
                    postingTo: sink)

                _ = try await engine.call(arguments: NoArguments())

                let events = await sink.events
                let kinds = events.map(\.kind)
                #expect(kinds.count == Self.progressSteps + Self.terminalEventCount, "kinds were: \(kinds)")
                #expect(kinds.last == .completed)
                #expect(kinds.dropLast().allSatisfy { $0 == .progress })
                #expect(events.last?.outcome == .succeeded)
                #expect(events.dropLast().allSatisfy { $0.outcome == nil })
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("two concurrent calls to the same tool produce events distinguishable by correlationID")
    func concurrentCallsAreDistinguishableByCorrelationID() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        try await MCPTestSupport.withConnection(of: server) {
            await Self.addProgressTool(to: scripted)
            try await withStubRun { run in
                // A caller-supplied sink, because this is the assertion that needs the
                // UNSTAMPED correlation: the mount's own sink re-stamps every event
                // onto the mounting run's token, which collapses two concurrent runs to
                // one correlation and makes this test inexpressible.
                let sink = RecordingEventSink()
                let engine = MCPCallProbe.mountedRunToCompletion(
                    Self.probe(server, tool: Self.progressToolName), on: run.context,
                    postingTo: sink)

                async let first = engine.call(arguments: NoArguments())
                async let second = engine.call(arguments: NoArguments())
                _ = try await (first, second)

                let events = await sink.events
                let correlationIDs = Set(events.map(\.correlationID))
                #expect(correlationIDs.count == Self.concurrentCallCount)
                for correlationID in correlationIDs {
                    let completed = events.filter { $0.correlationID == correlationID && $0.kind == .completed }
                    #expect(completed.count == Self.terminalEventCount)
                }
            }
        }
        withExtendedLifetime(scripted) {}
    }
}
