import Logging
import MCP
import MCPTestServer
import TelemetryTestSupport
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the swift-log records of the MCP capability files: a connect
/// that fails, a reconnect, and a tool call that fails because the transport
/// dropped.
///
/// Each case gives the server the logger of a `TelemetryCapture`, because
/// `MCPServer` logs from its own tasks. Each case gives the capture the
/// content of the fixture — the text of an error, a tool argument — as
/// forbidden strings, so a record that carries that content fails the case.
@Suite("MCPLogRecords")
struct MCPLogRecordTests {
    // MARK: - Fixture content

    /// The name of each server of this suite.
    private static let serverName = "mcp-log-record-server"

    /// The text of the error of each failed connect attempt. No record may
    /// carry it.
    private static let errorMarker = "qzvConnectErrorMarker"

    /// The value of the tool argument of the failed call. No record may carry
    /// it.
    private static let argumentMarker = "qzvCallArgumentMarker"

    /// The name of the tool argument of the failed call.
    private static let argumentName = "city"

    /// The name of the tool that does not answer.
    private static let hangingToolName = "hanging-tool"

    /// How long the tool that does not answer sleeps: longer than the test.
    private static let hangingToolSleep = Duration.seconds(3600)

    /// How many connect attempts the flaky transport fails: more than the
    /// policy allows.
    private static let manyFailingAttempts = 10

    /// The attempt budget of the failed connect.
    private static let attemptLimit = 3

    /// The per-attempt timeout of the failed connect. No attempt reaches it.
    private static let connectTimeout = Duration.seconds(10)

    /// The delay between two attempts of the failed connect.
    private static let backoffDelay = Duration.milliseconds(10)

    /// The count of calls in flight when the transport drops.
    private static let oneCallInFlight = 1

    /// The policy of the failed connect.
    private static let failingPolicy = BackoffPolicy(
        connectTimeout: connectTimeout, baseDelay: backoffDelay, maxDelay: backoffDelay,
        maxAttempts: attemptLimit)

    /// The error of each failed connect attempt. Its text holds
    /// ``errorMarker``.
    private struct MarkedConnectError: Error, CustomStringConvertible {
        /// The text of the error.
        var description: String { MCPLogRecordTests.errorMarker }
    }

    /// The tool that does not answer. `counter` counts the calls of its
    /// handler.
    ///
    /// - Parameter counter: The counter of the calls.
    /// - Returns: The scripted tool.
    private static func hangingTool(counting counter: CallCounter) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: hangingToolName,
                description: "Does not answer.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            counter.increment()
            try await Task.sleep(for: hangingToolSleep)
            return CallTool.Result(content: [])
        }
    }

    /// Records a failure unless the server of this suite wrote `record`: the
    /// record names the server, and the logger that the case gave the server
    /// wrote it.
    ///
    /// - Parameter record: The log record.
    private static func expectWrittenByTheServer(_ record: TelemetryCapture.LogRecord) {
        #expect(record.metadataText(MultitoolTelemetry.AttributeKey.serverName) == serverName)
        #expect(record.label == LogReadback.captureLoggerLabel)
    }

    // MARK: - A failed connect

    @Test("a connect that uses all its attempts logs each attempt and the end, with the server name and not the error text")
    func failedConnectLogsEachAttemptAndTheEnd() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.manyFailingAttempts,
            error: MarkedConnectError())

        let records = try await TelemetryCapture.run(forbidding: [Self.errorMarker]) { context in
            let server = MCPServer(name: Self.serverName, clock: ManualClock(), logger: context.logger)
            await #expect(throws: MCPServerError.self) {
                try await server.connect(via: flaky, backoffPolicy: Self.failingPolicy)
            }
            return context.logRecords
        }

        let failed = LogReadback.records(.mcpConnectAttemptFailed, in: records)
        #expect(failed.count == Self.attemptLimit)
        for record in failed {
            #expect(record.level == .warning)
            Self.expectWrittenByTheServer(record)
            #expect(record.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) != nil)
            #expect(record.metadataText(MultitoolTelemetry.LogMetadataKey.connectAttemptLimit) == "\(Self.attemptLimit)")
        }

        let exhausted = try #require(LogReadback.records(.mcpConnectBackoffExhausted, in: records).first)
        #expect(exhausted.level == .error)
        Self.expectWrittenByTheServer(exhausted)
        #expect(exhausted.metadataText(MultitoolTelemetry.LogMetadataKey.connectAttemptLimit) == "\(Self.attemptLimit)")
        #expect(exhausted.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) != nil)
    }

    // MARK: - A reconnect

    @Test("a reconnect logs an info record with the server name")
    func reconnectLogsAnInfoRecord() async throws {
        let respawning = RespawningTransport.makeServingFreshScriptedServers { ScriptedServer() }

        let records = try await TelemetryCapture.run(forbidding: []) { context in
            let server = MCPServer(name: Self.serverName, logger: context.logger)
            try await server.connect(via: respawning, backoffPolicy: .default)
            await respawning.disconnect()
            try await server.reconnect()
            return context.logRecords
        }

        let reconnected = try #require(LogReadback.records(.mcpReconnected, in: records).first)
        #expect(reconnected.level == .info)
        Self.expectWrittenByTheServer(reconnected)
        let succeeded = try #require(LogReadback.records(.mcpConnectAttemptSucceeded, in: records).last)
        #expect(succeeded.level == .info)
        Self.expectWrittenByTheServer(succeeded)
    }

    // MARK: - A tool call that fails

    @Test("a transport drop under a tool call logs a warning with the server name and the call count, and not the argument")
    func transportDropUnderACallLogsAWarning() async throws {
        let counter = CallCounter()
        let respawning = RespawningTransport.makeServingFreshScriptedServers {
            let scripted = ScriptedServer()
            await scripted.addTool(Self.hangingTool(counting: counter))
            return scripted
        }

        let records = try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            let server = MCPServer(name: Self.serverName, logger: context.logger)
            try await server.connect(via: respawning, backoffPolicy: .default)
            let call = Task {
                try await server.call(
                    name: Self.hangingToolName,
                    arguments: [Self.argumentName: .string(Self.argumentMarker)])
            }
            try await TestPoll.waitUntil("the handler ran") { counter.count == Self.oneCallInFlight }
            await respawning.disconnect()
            try await TestPoll.waitUntil("the server noticed the drop") { await server.isTransportDropped }
            await #expect(throws: MCPServerError.self) {
                _ = try await call.value
            }
            return context.logRecords
        }

        let dropped = try #require(LogReadback.records(.mcpTransportDropped, in: records).first)
        #expect(dropped.level == .warning)
        Self.expectWrittenByTheServer(dropped)
        #expect(dropped.metadataText(MultitoolTelemetry.LogMetadataKey.itemCount) == "\(Self.oneCallInFlight)")
    }
}
