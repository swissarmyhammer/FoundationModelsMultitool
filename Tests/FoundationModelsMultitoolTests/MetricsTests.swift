import FoundationModelsExtras
import MCP
import MCPTestServer
import MetricsTestKit
import TelemetryTestSupport
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the swift-metrics metrics of the library target.
///
/// FoundationModelsExtras records `FoundationModelsExtras.tool.calls` and
/// `FoundationModelsExtras.tool.duration` for each call of a mounted tool.
/// Thus the library records its own tool-call metrics only for an inner
/// `tools.*` call that no Extras mount holds: the native call, when no session
/// bound a context. The library also records the errors and the restarts of
/// an MCP server, and the duration of each run of the JS interpreter.
///
/// Each case runs in a `TelemetryCapture`, which binds an in-memory metrics
/// factory to the task of the case. Each case gives the capture the content of
/// the fixture (an argument, a result, JS text) as forbidden strings, thus a
/// metric dimension that carries that content fails the case.
@Suite("Metrics")
struct MetricsTests {
    // MARK: - Fixture content

    /// The city argument of a `tools.*` call. No dimension may carry it.
    private static let argumentMarker = "qzvMetricArgumentMarker"

    /// The text of the result of an MCP tool. No dimension may carry it.
    private static let resultMarker = "qzvMetricResultMarker"

    /// The text of the error that a snippet throws. No dimension may carry it.
    private static let errorMarker = "qzvMetricErrorMarker"

    /// The name of each MCP server of this suite.
    private static let serverName = "mcp-metrics-server"

    /// The name of the MCP tool that answers with `isError` set.
    private static let failingToolName = "failing-tool"

    /// The name of the MCP tool that does not answer.
    private static let hangingToolName = "hanging-tool"

    /// The name of the argument of each MCP call.
    private static let argumentName = "city"

    /// How long the MCP tool that does not answer sleeps: longer than the test.
    private static let hangingToolSleep = Duration.seconds(3600)

    /// The bound of a bare MCP call in the timeout case: short, so the case
    /// ends soon.
    private static let shortCallTimeout = Duration.milliseconds(100)

    /// The time limit of the interpreter in the time limit case, in seconds.
    private static let shortTimeLimit = 0.2

    /// The name of the inner tool of the `runCode` cases.
    private static let innerToolName = TempTool().name

    /// The counter that FoundationModelsExtras records for each mounted tool
    /// call. The Extras vocabulary is internal to Extras, thus the case names
    /// the label as text.
    private static let extrasToolCallsLabel = "FoundationModelsExtras.tool.calls"

    /// The dimension of the tool name of the Extras tool-call metrics.
    private static let extrasToolNameKey = "tool.name"

    /// One count, or one recorded duration.
    private static let once = 1

    // MARK: - Helpers

    /// The dimensions of a tool-call metric of the library, in the order of
    /// ``MultitoolTelemetry/MetricName/dimensionKeys``.
    ///
    /// - Parameters:
    ///   - toolName: The tool name.
    ///   - outcome: The outcome.
    /// - Returns: The dimensions.
    private static func toolDimensions(
        _ toolName: String, _ outcome: MultitoolTelemetry.OutcomeValue
    ) -> [(String, String)] {
        [
            (MultitoolTelemetry.AttributeKey.toolName.rawValue, toolName),
            (MultitoolTelemetry.AttributeKey.outcome.rawValue, outcome.rawValue),
        ]
    }

    /// The dimensions of the interpreter timer.
    ///
    /// - Parameter outcome: The outcome of the run.
    /// - Returns: The dimensions.
    private static func runDimensions(_ outcome: MultitoolTelemetry.OutcomeValue) -> [(String, String)] {
        [(MultitoolTelemetry.AttributeKey.outcome.rawValue, outcome.rawValue)]
    }

    /// The dimensions of the MCP error counter.
    ///
    /// - Parameter kind: The kind of the error.
    /// - Returns: The dimensions.
    private static func errorDimensions(_ kind: MultitoolTelemetry.ErrorKindValue) -> [(String, String)] {
        [
            (MultitoolTelemetry.AttributeKey.serverName.rawValue, serverName),
            (MultitoolTelemetry.AttributeKey.errorKind.rawValue, kind.rawValue),
        ]
    }

    /// The dimensions of the MCP restart counter.
    private static let restartDimensions = [(MultitoolTelemetry.AttributeKey.serverName.rawValue, serverName)]

    /// The counters of `context` with the label of `metric`.
    ///
    /// - Parameters:
    ///   - metric: The metric.
    ///   - context: The capture.
    /// - Returns: The counters.
    private static func counters(
        _ metric: MultitoolTelemetry.MetricName, in context: TelemetryCapture.Context
    ) -> [TestCounter] {
        context.metricsFactory.counters.filter { $0.label == metric.rawValue }
    }

    /// A `runCode` over the fixture tools of this suite.
    ///
    /// - Returns: The tool.
    /// - Throws: What `MultiTool.Builder.buildRegistry()` throws.
    private static func makeMultiTool() throws -> MultiTool {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .addTool(ThrowingTool())
            .buildRegistry()
        return MultiTool(registry: registry)
    }

    /// A snippet that calls the inner tool `toolName` one time.
    ///
    /// - Parameter toolName: The name of the inner tool.
    /// - Returns: The snippet.
    private static func snippet(calling toolName: String) -> String {
        "return await tools.\(toolName)({ city: '\(argumentMarker)' });"
    }

    /// An MCP tool that answers with `isError` set and one text block of
    /// ``resultMarker``.
    private static var failingTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: failingToolName, description: "Answers with an error.", inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            CallTool.Result(content: [.text(text: resultMarker, annotations: nil, _meta: nil)], isError: true)
        }
    }

    /// An MCP tool that does not answer.
    private static var hangingTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: hangingToolName, description: "Does not answer.", inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            try await Task.sleep(for: hangingToolSleep)
            return CallTool.Result(content: [])
        }
    }

    /// A scripted server that serves `tool`.
    ///
    /// - Parameter tool: The tool to serve.
    /// - Returns: The scripted server.
    private static func scriptedServer(serving tool: ScriptedTool) async -> ScriptedServer {
        let scripted = ScriptedServer()
        await scripted.addTool(tool)
        return scripted
    }

    // MARK: - The inner tools.* dispatch

    @Test("a runCode call with no session records the count and the duration of its native tools.* call, and one interpreter run")
    func nativeInnerCallRecordsTheToolMetrics() async throws {
        let multiTool = try Self.makeMultiTool()
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            _ = try await multiTool.call(arguments: RunCodeArguments(code: Self.snippet(calling: Self.innerToolName)))

            let dimensions = Self.toolDimensions(Self.innerToolName, .succeeded)
            let calls = try context.metricsFactory.expectCounter(MultitoolTelemetry.MetricName.toolCalls.rawValue, dimensions)
            #expect(calls.totalValue == Int64(Self.once))
            let duration = try context.metricsFactory.expectTimer(
                MultitoolTelemetry.MetricName.toolDuration.rawValue, dimensions)
            #expect(duration.values.count == Self.once)
            #expect(Self.counters(.toolCalls, in: context).count == Self.once)

            let run = try context.metricsFactory.expectTimer(
                MultitoolTelemetry.MetricName.interpreterRunDuration.rawValue, Self.runDimensions(.succeeded))
            #expect(run.values.count == Self.once)
        }
    }

    @Test("a native tools.* call that throws records the outcome threw")
    func nativeInnerCallThatThrowsRecordsThrew() async throws {
        let multiTool = try Self.makeMultiTool()
        let toolName = ThrowingTool().name
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            _ = try await multiTool.call(arguments: RunCodeArguments(code: Self.snippet(calling: toolName)))

            let calls = try context.metricsFactory.expectCounter(
                MultitoolTelemetry.MetricName.toolCalls.rawValue, Self.toolDimensions(toolName, .threw))
            #expect(calls.totalValue == Int64(Self.once))
        }
    }

    @Test("a tools.* call under a session goes through the Extras mount: Extras counts it, and the library does not count it again")
    func mountedInnerCallIsCountedByExtrasOnly() async throws {
        let multiTool = try Self.makeMultiTool()
        let toolContext = try await makeOuterRunContext()
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            _ = try await ToolContext.$current.withValue(toolContext) {
                try await multiTool.call(arguments: RunCodeArguments(code: Self.snippet(calling: Self.innerToolName)))
            }

            let extrasCalls = context.metricsFactory.counters.filter { counter in
                counter.label == Self.extrasToolCallsLabel
                    && counter.dimensions.contains { $0 == (Self.extrasToolNameKey, Self.innerToolName) }
            }
            #expect(extrasCalls.count == Self.once)
            #expect(Self.counters(.toolCalls, in: context).isEmpty)
        }
    }

    // MARK: - MCP servers

    @Test("an MCP call whose result has isError set records one error with the kind isError")
    func isErrorResultRecordsAnError() async throws {
        let scripted = await Self.scriptedServer(serving: Self.failingTool)
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker, Self.resultMarker]) { context in
            let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, logger: context.logger)
            _ = try await server.call(
                name: Self.failingToolName, arguments: [Self.argumentName: .string(Self.argumentMarker)])

            let errors = try context.metricsFactory.expectCounter(
                MultitoolTelemetry.MetricName.mcpServerErrors.rawValue, Self.errorDimensions(.isError))
            #expect(errors.totalValue == Int64(Self.once))
            #expect(Self.counters(.mcpServerErrors, in: context).count == Self.once)
        }
    }

    @Test("a bare MCP call that times out records one error with the kind timeout, and no isError")
    func timedOutCallRecordsATimeout() async throws {
        let scripted = await Self.scriptedServer(serving: Self.hangingTool)
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, callTimeout: Self.shortCallTimeout, logger: context.logger)
            _ = try await server.call(
                name: Self.hangingToolName, arguments: [Self.argumentName: .string(Self.argumentMarker)])

            let errors = try context.metricsFactory.expectCounter(
                MultitoolTelemetry.MetricName.mcpServerErrors.rawValue, Self.errorDimensions(.timeout))
            #expect(errors.totalValue == Int64(Self.once))
            #expect(Self.counters(.mcpServerErrors, in: context).count == Self.once)
        }
    }

    @Test("the first connect records no restart, and a reconnect with a fresh transport records one")
    func reconnectRecordsARestart() async throws {
        let respawning = RespawningTransport.makeServingFreshScriptedServers { ScriptedServer() }
        try await TelemetryCapture.run(forbidding: []) { context in
            let server = MCPServer(name: Self.serverName, logger: context.logger)
            try await server.connect(via: respawning, backoffPolicy: .default)
            #expect(Self.counters(.mcpServerRestarts, in: context).isEmpty)

            await respawning.disconnect()
            try await server.reconnect()

            let restarts = try context.metricsFactory.expectCounter(
                MultitoolTelemetry.MetricName.mcpServerRestarts.rawValue, Self.restartDimensions)
            #expect(restarts.totalValue == Int64(Self.once))
        }
    }

    // MARK: - The JS interpreter

    @Test("a JS run that throws records the interpreter timer with the outcome threw")
    func throwingRunRecordsThrew() async throws {
        try await TelemetryCapture.run(forbidding: [Self.errorMarker]) { context in
            await #expect(throws: InterpreterError.self) {
                try await JSCInterpreter().run(code: "throw new Error('\(Self.errorMarker)');", installing: [])
            }

            let run = try context.metricsFactory.expectTimer(
                MultitoolTelemetry.MetricName.interpreterRunDuration.rawValue, Self.runDimensions(.threw))
            #expect(run.values.count == Self.once)
        }
    }

    @Test("a JS run that passes its time limit records the interpreter timer with the outcome timedOut")
    func timedOutRunRecordsTimedOut() async throws {
        try await TelemetryCapture.run(forbidding: []) { context in
            await #expect(throws: InterpreterError.self) {
                try await JSCInterpreter(timeLimit: Self.shortTimeLimit).run(code: "while (true) {}", installing: [])
            }

            let run = try context.metricsFactory.expectTimer(
                MultitoolTelemetry.MetricName.interpreterRunDuration.rawValue, Self.runDimensions(.timedOut))
            #expect(run.values.count == Self.once)
        }
    }
}
