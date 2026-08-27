import FoundationModels
import FoundationModelsRouter
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the `lost` terminal outcome: a dropped transport destroys the
/// only channel a result was ever going to arrive on, so the outcome is
/// unknowable, never a reported failure, and never auto-retried by this
/// package.
///
/// A port of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/LostCallTests.swift`,
/// adapted to the ambient context: the sibling read the outcome off a sink
/// its `MCPTool` was connected to; here the engine of Router settles the run,
/// and the sink the engine was given records the terminal event. The cases
/// that are here:
///
/// - `midCallTransportFaultPostsLostOutcome`, as
///   `aTransportDroppedBeforeTheCallThrowsLost`
/// - `noAutoRetryAfterReconnectEvenForIdempotentHintedTool`
///
/// The cases of the source that are not here, and why:
///
/// - `killingConnectionSettlesEveryDetachedCallAsLost` — a detach case. A
///   call never detaches: it runs inside the run that called it, and the
///   sweep of every in-flight call on a drop stands in
///   `aTransportDroppedBeforeTheCallThrowsLost` with one call.
/// - `getResultReportsLossThenNotFoundAfterEviction` — a `get_result` case.
///   The builtins of the run plane replaced the follow-up tools, and the
///   server retains no settled call.
///
/// The other terminal outcomes are covered by `MCPServerCallTests`; this suite
/// covers only what is new here.
@Suite("LostCallTests")
struct LostCallTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with.
    private static let serverName = "lost-call-test-server"

    /// The text the echo case sends.
    private static let echoText = "hi"

    /// The name of the tool that hangs forever.
    private static let hangingToolName = "idempotent-hang"

    /// How long the hanging tool sleeps once invoked — long enough that it
    /// never returns during the lifetime of this test.
    private static let hangingToolSleep = Duration.seconds(3600)

    /// How long the no-auto-retry case waits after the reconnect before it
    /// asserts the handler never ran again — giving an (incorrect) auto-retry
    /// a fair chance to have fired first.
    private static let autoRetryGraceWindow = Duration.milliseconds(300)

    /// How many times the handler of the hanging tool ran: exactly the one
    /// call the test made.
    private static let oneInvocation = 1

    /// How many terminal events one run posts.
    private static let terminalEventCount = 1

    // MARK: - Helpers

    /// The hanging tool, annotated idempotent so a retry would be "safe";
    /// `counter` ticks once per invocation of its handler.
    ///
    /// - Parameter counter: The oracle of the no-auto-retry case.
    /// - Returns: The scripted tool.
    private static func hangingTool(counting counter: CallCounter) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: hangingToolName,
                description: "Hangs forever; annotated idempotent so a retry would be safe.",
                inputSchema: JSONSchemaBuilder.emptySchema,
                annotations: MCP.Tool.Annotations(idempotentHint: true))
        ) { _ in
            counter.increment()
            try await Task.sleep(for: hangingToolSleep)
            return CallTool.Result(content: [])
        }
    }

    // MARK: - A transport drop settles the call as lost

    /// The transport is severed before the call is made, so the request
    /// meets a dead connection — the "scripted transport drop" of
    /// `ResilienceTests`, for this suite's own outcome assertion.
    @Test("a transport dropped before the call throws lost, and the run posts exactly one completed event with outcome lost")
    func aTransportDroppedBeforeTheCallThrowsLost() async throws {
        let respawning = RespawningTransport.makeServingFreshScriptedServers {
            let scripted = ScriptedServer()
            await scripted.addEchoTool()
            return scripted
        }
        let server = MCPServer(name: Self.serverName)
        try await server.connect(via: respawning, backoffPolicy: .default)
        let sink = RecordingEventSink()
        let engine = try MCPCallProbe.mountedRunToCompletion(
            MCPCallProbeTool(
                server: server, toolName: ScriptedServer.echoToolName,
                callArguments: [ScriptedServer.echoTextArgument: .string(Self.echoText)]),
            mailbox: SessionMailbox(), sink: sink)

        await respawning.disconnect()
        try await TestPoll.waitUntil("the server noticed the drop") {
            await server.isTransportDropped
        }
        let thrown = await MCPCallProbe.thrownError {
            _ = try await engine.call(arguments: NoArguments())
        }

        guard case .lost? = thrown as? MCPServerError else {
            Issue.record("expected MCPServerError.lost, got \(String(describing: thrown))")
            return
        }
        let completed = await sink.events.filter { $0.kind == .completed }
        #expect(completed.count == Self.terminalEventCount)
        // `.lost` must never flatten into `.failed` in the shared envelope
        // vocabulary — the outcome is unknowable, not a reported failure.
        #expect(completed.first?.outcome == .lost)
    }

    // MARK: - Never auto-retried, regardless of ToolAnnotations

    /// A forward-looking regression guard, not a test of the `lost`
    /// classification itself: this package never resends a request, so this
    /// call counter stays at one. What it locks in is the decision — never
    /// wire `idempotentHint`, or any other `ToolAnnotations` hint, into an
    /// auto-retry later, even for a `lost` call — so a future change that
    /// adds one trips this test.
    @Test("no call is re-sent after reconnect, even for a tool annotated idempotentHint: true")
    func noAutoRetryAfterReconnectEvenForIdempotentHintedTool() async throws {
        let counter = CallCounter()
        let respawning = RespawningTransport.makeServingFreshScriptedServers {
            let scripted = ScriptedServer()
            await scripted.addTool(Self.hangingTool(counting: counter))
            return scripted
        }
        let server = MCPServer(name: Self.serverName)
        try await server.connect(via: respawning, backoffPolicy: .default)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let callTask = Task {
            try await ToolContext.$current.withValue(context) {
                try await server.call(name: Self.hangingToolName, arguments: nil)
            }
        }
        try await TestPoll.waitUntil("the handler ran") { counter.count == Self.oneInvocation }
        await respawning.disconnect()

        let thrown = await MCPCallProbe.thrownError {
            _ = try await callTask.value
        }
        guard case .lost? = thrown as? MCPServerError else {
            Issue.record("expected MCPServerError.lost, got \(String(describing: thrown))")
            return
        }

        try await server.reconnect()
        #expect(await server.state == .ready)
        // Give an (incorrect) auto-retry a fair chance to have fired before
        // asserting it never did.
        try await Task.sleep(for: Self.autoRetryGraceWindow)
        #expect(counter.count == Self.oneInvocation)
    }
}
