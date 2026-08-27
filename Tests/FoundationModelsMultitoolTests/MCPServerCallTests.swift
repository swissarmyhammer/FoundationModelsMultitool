import Foundation
import FoundationModels
import FoundationModelsRouter
import MCP
import MCPTestServer
import Testing
import ULID

@testable import FoundationModelsMultitool

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
/// Each test binds a `ToolContext` with a recording sink around the call, the
/// way `ShellExecuteTests` does, and the `.lost` settlement case runs the call
/// inside a mounted `MultiTool` over a real `SessionMailbox`.
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

    /// How long the short progress tool waits between notifications.
    private static let progressStepDelay = Duration.milliseconds(5)

    /// How many progress notifications the long-running tool sends — far
    /// more than a test lets run, so the call is still in flight when the
    /// test acts on it.
    private static let longRunSteps = 1_000

    /// How long the long-running tool waits between notifications.
    private static let longRunStepDelay = Duration.milliseconds(20)

    /// How long a test waits for the scripted server to record a
    /// `notifications/cancelled`.
    private static let notificationTimeout = Duration.seconds(5)

    /// How many recorded notifications the cancel cases wait for.
    private static let oneNotification = 1

    /// The name of the tool that drops the transport mid-call.
    private static let droppingToolName = "drops"

    /// The name of the tool that answers an `isError` result.
    private static let failingToolName = "fails"

    /// The text the failing tool answers.
    private static let failingToolText = "nope"

    /// The name of the tool that never answers in time.
    private static let stallingToolName = "stalls"

    /// How long the stalling tool sleeps — far past the bare-call timeout of
    /// its test.
    private static let stallingToolSleep = Duration.seconds(30)

    /// The bound of the bare call of the timeout case — short, because the
    /// test proves it bounds real time.
    private static let bareCallTimeout = Duration.milliseconds(50)

    /// How many terminal events one run posts.
    private static let terminalEventCount = 1

    /// How many concurrent calls the correlation case makes.
    private static let concurrentCallCount = 2

    /// The `runCode` snippet that awaits the probe and returns its answer.
    private static let probeSnippet = "return await tools.\(MCPCallProbeTool.probeName)();"

    // MARK: - Helpers

    /// A scripted server that serves `tools`, connected to a fresh
    /// `MCPServer` named ``serverName`` over the in-memory transport — the
    /// shared ``MCPTestSupport/connectedMCPServer(serving:name:callTimeout:renderBudget:)``
    /// under this suite's own name.
    ///
    /// - Parameters:
    ///   - tools: The tools to register before the connect.
    ///   - callTimeout: The bound of a bare call of the server.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        serving tools: [ScriptedTool], callTimeout: Duration = MCPServer.defaultCallTimeout
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedMCPServer(
            serving: tools, name: serverName, callTimeout: callTimeout)
    }

    /// A scripted tool that answers `result` after `delay`.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - delay: How long the handler sleeps before it answers.
    ///   - result: The result the handler answers.
    /// - Returns: The scripted tool.
    private static func delayedTool(
        named name: String, delay: Duration, answering result: CallTool.Result
    ) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: name, description: "Answers after a delay.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            try await Task.sleep(for: delay)
            return result
        }
    }

    /// A scripted tool that answers an `isError` result at once.
    private static var failingTool: ScriptedTool {
        delayedTool(
            named: failingToolName, delay: .zero,
            answering: CallTool.Result(
                content: [.text(text: failingToolText, annotations: nil, _meta: nil)],
                isError: true))
    }

    /// The progress-reporting tool of the short progress cases.
    ///
    /// - Parameter scripted: The server to register it on.
    private static func addProgressTool(to scripted: ScriptedServer) async {
        await scripted.addProgressReportingTool(
            named: progressToolName, totalSteps: progressSteps, stepDelay: progressStepDelay)
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

    // MARK: - The result

    @Test("a call against ScriptedServer returns the server's result")
    func aCallReturnsTheServersResult() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let result = try await Self.call(
            server, tool: ScriptedServer.echoToolName,
            arguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)],
            under: context)

        #expect(result.isError != true)
        #expect(result.content == [.text(text: Self.echoText, annotations: nil, _meta: nil)])
        withExtendedLifetime(scripted) {}
    }

    /// The card's contract: a result with `isError: true` returns as a value,
    /// and the renderer keeps it in band.
    @Test("a result with isError returns as a value")
    func anIsErrorResultReturnsAsAValue() async throws {
        let (scripted, server) = try await Self.connected(serving: [Self.failingTool])
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let result = try await Self.call(server, tool: Self.failingToolName, under: context)

        #expect(result.isError == true)
        #expect(result.content == [.text(text: Self.failingToolText, annotations: nil, _meta: nil)])
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Progress

    @Test("a progress notification during a call reaches ToolContext.progress with the run's correlationID")
    func progressReachesTheAmbientContext() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await Self.addProgressTool(to: scripted)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        _ = try await Self.call(server, tool: Self.progressToolName, under: context)

        let progress = await sink.events.filter { $0.kind == .progress }
        #expect(progress.count == Self.progressSteps, "progress was: \(progress)")
        #expect(progress.allSatisfy { $0.correlationID == context.completionToken })
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Cancellation

    @Test("cancellation of the calling Task sends notifications/cancelled and the call throws CancellationError")
    func cancellationSendsTheNotificationAndThrows() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await scripted.addProgressReportingTool(
            named: Self.progressToolName, totalSteps: Self.longRunSteps,
            stepDelay: Self.longRunStepDelay)
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        let callTask = Task {
            try await Self.call(server, tool: Self.progressToolName, under: context)
        }
        try await TestPoll.waitUntil("the call reported progress") {
            await !sink.details(ofKind: .progress).isEmpty
        }
        callTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await callTask.value
        }
        let recorded = await scripted.waitForRecordedNotifications(
            count: Self.oneNotification, timeout: Self.notificationTimeout)
        #expect(recorded.first?.method == CancelledNotification.name)
    }

    // MARK: - The transport drop

    @Test("a transport drop mid-call throws MCPServerError.lost, and that value is a LostRunError")
    func aTransportDropMidCallThrowsLost() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await scripted.addTransportDroppingTool(named: Self.droppingToolName)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let thrown = await MCPCallProbe.thrownError {
            _ = try await Self.call(server, tool: Self.droppingToolName, under: context)
        }

        guard case .lost? = thrown as? MCPServerError else {
            Issue.record("expected MCPServerError.lost, got \(String(describing: thrown))")
            return
        }
        #expect(thrown is any LostRunError)
        withExtendedLifetime(scripted) {}
    }

    /// eventplan.md § "Phases", the phase-4 note: "A transport drop under an
    /// in-flight request throws a `LostRunError` (Router), and the engine
    /// settles the calling run as `.lost`."
    @Test("a background runCode run whose snippet awaits the call across a transport drop settles as lost")
    func aBackgroundRunAcrossATransportDropSettlesAsLost() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await scripted.addTransportDroppingTool(named: Self.droppingToolName)
        let registry = try MultiTool.Builder()
            .addTool(Self.probe(server, tool: Self.droppingToolName))
            .buildRegistry()
        let mailbox = SessionMailbox()
        let mounted = try #require(
            ToolMounting.makeWrapped(
                tool: MultiTool(registry: registry),
                sessionID: ULID(),
                mailbox: mailbox,
                sink: RecordingEventSink(),
                configuration: .synchronous
            ) as? any FoundationModels.Tool<RunCodeArguments, String>
        )

        let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.probeSnippet))

        #expect(PendingRunEnvelope.isRendered(text: rendered), "answer was: \(rendered)")
        let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        let settlement = await backgroundRuns(over: mailbox).wait(
            completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds)
        guard case .settled(let terminal) = settlement else {
            Issue.record("the background run never settled: \(settlement)")
            return
        }
        #expect(terminal.outcome == .lost, "terminal was: \(terminal)")
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The in-band answers of the call path

    /// A server that is not `.ready` cannot carry a request, and the call
    /// answers in band: the model reads why, and the engine reports the run
    /// as it reports any answered call.
    @Test("a call on a server that is not ready answers an isError result in band")
    func aCallOnAServerThatIsNotReadyAnswersInBand() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())
        await server.disconnect()

        let result = try await Self.call(server, tool: ScriptedServer.echoToolName, under: context)

        #expect(result.isError == true)
        #expect(
            ToolContentRenderer.render(result: result, budget: RenderBudget.default)
                .contains(Self.serverName))
        withExtendedLifetime(scripted) {}
    }

    /// A call with no ambient context has no engine to bound it, so the
    /// server's own `callTimeout` does: the request is cancelled on the wire,
    /// and the call answers in band.
    @Test("a call with no ambient context is bounded by callTimeout and answers in band")
    func aBareCallIsBoundedByTheCallTimeout() async throws {
        let (scripted, server) = try await Self.connected(
            serving: [
                Self.delayedTool(
                    named: Self.stallingToolName, delay: Self.stallingToolSleep,
                    answering: CallTool.Result(content: []))
            ],
            callTimeout: Self.bareCallTimeout)

        let result = try await server.call(name: Self.stallingToolName, arguments: nil)

        #expect(result.isError == true)
        let recorded = await scripted.waitForRecordedNotifications(
            count: Self.oneNotification, timeout: Self.notificationTimeout)
        #expect(recorded.first?.method == CancelledNotification.name)
    }

    // MARK: - The progress cases of OperationEventsTests

    /// The engine posts every progress event before the one terminal event,
    /// and the terminal event carries the outcome.
    @Test("a mounted call posts its progress events then exactly one completed, in that order")
    func progressThenExactlyOneCompleted() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await Self.addProgressTool(to: scripted)
        let sink = RecordingEventSink()
        let engine = try MCPCallProbe.mountedRunToCompletion(
            Self.probe(server, tool: Self.progressToolName), mailbox: SessionMailbox(), sink: sink)

        _ = try await engine.call(arguments: NoArguments())

        let events = await sink.events
        let kinds = events.map(\.kind)
        #expect(kinds.count == Self.progressSteps + Self.terminalEventCount, "kinds were: \(kinds)")
        #expect(kinds.last == .completed)
        #expect(kinds.dropLast().allSatisfy { $0 == .progress })
        #expect(events.last?.outcome == .succeeded)
        #expect(events.dropLast().allSatisfy { $0.outcome == nil })
        withExtendedLifetime(scripted) {}
    }

    @Test("two concurrent calls to the same tool produce events distinguishable by correlationID")
    func concurrentCallsAreDistinguishableByCorrelationID() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await Self.addProgressTool(to: scripted)
        let sink = RecordingEventSink()
        let engine = try MCPCallProbe.mountedRunToCompletion(
            Self.probe(server, tool: Self.progressToolName), mailbox: SessionMailbox(), sink: sink)

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
        withExtendedLifetime(scripted) {}
    }
}
