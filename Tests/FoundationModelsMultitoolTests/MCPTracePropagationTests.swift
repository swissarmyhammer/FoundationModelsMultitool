import Foundation
import FoundationModelsExtras
import InMemoryLogging
import InMemoryTracing
import MCP
import MCPTestServer
import TelemetryTestSupport
import Testing
import Tracing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the client span of each MCP `tools/call`, and for the W3C
/// trace context that the request carries in its `_meta`.
///
/// Each case runs in a `TelemetryCapture`. The tracer of the capture is a
/// `W3CInMemoryTracer`: it injects the span context as a W3C `traceparent`
/// value. Thus the `_meta` that the ``WireRecordingTransport`` records on the
/// wire holds the trace id and the span id of the client span. Each case
/// gives the capture the tool argument and the result text of the fixture as
/// forbidden strings, so a span or a record that carries MCP content fails the
/// case.
@Suite("MCPTracePropagation")
struct MCPTracePropagationTests {
    // MARK: - Fixture content

    /// The name of each server of this suite.
    private static let serverName = "mcp-trace-server"

    /// The name of the tool that answers with a text.
    private static let echoToolName = "echo-tool"

    /// The name of the tool that answers with an `isError` result.
    private static let failingToolName = "failing-tool"

    /// The name of the tool that does not answer.
    private static let hangingToolName = "hanging-tool"

    /// The name of the tool argument of each call.
    private static let argumentName = "city"

    /// The value of the tool argument of each call. No span and no record may
    /// carry it.
    private static let argumentMarker = "qzvTraceArgumentMarker"

    /// The text of the result of each tool that answers. No span and no
    /// record may carry it.
    private static let resultMarker = "qzvTraceResultMarker"

    /// The name of the span that the test opens around a call.
    private static let parentSpanName = "test.parent"

    /// The key of the progress token in the `_meta` of a request.
    private static let progressTokenKey = "progressToken"

    /// The version field that each `traceparent` value of the tracer starts
    /// with.
    private static let traceparentVersionPrefix = "00-"

    /// The bound of a bare call in the timeout case: short, so the case ends
    /// soon.
    private static let shortCallTimeout = Duration.milliseconds(100)

    /// How long the tool that does not answer sleeps: longer than the test.
    private static let hangingToolSleep = Duration.seconds(3600)

    /// The count of calls in flight when the transport drops or the server
    /// reconnects.
    private static let oneCallInFlight = 1

    // MARK: - Fixture tools

    /// A tool that answers `result` with one text block of ``resultMarker``.
    ///
    /// - Parameters:
    ///   - name: The name of the tool.
    ///   - isError: The `isError` flag of the result.
    /// - Returns: The scripted tool.
    private static func answeringTool(named name: String, isError: Bool) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: name, description: "Answers with a text.", inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            CallTool.Result(
                content: [.text(text: resultMarker, annotations: nil, _meta: nil)], isError: isError)
        }
    }

    /// The tool that does not answer. `counter` counts the calls of its
    /// handler.
    ///
    /// - Parameter counter: The counter of the calls.
    /// - Returns: The scripted tool.
    private static func hangingTool(counting counter: CallCounter) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: hangingToolName, description: "Does not answer.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            counter.increment()
            try await Task.sleep(for: hangingToolSleep)
            return CallTool.Result(content: [])
        }
    }

    /// A scripted server that serves `tools`.
    ///
    /// - Parameter tools: The tools to serve.
    /// - Returns: The scripted server.
    private static func scriptedServer(serving tools: [ScriptedTool]) async -> ScriptedServer {
        let scripted = ScriptedServer()
        for tool in tools {
            await scripted.addTool(tool)
        }
        return scripted
    }

    /// The arguments of each call: one argument that holds
    /// ``argumentMarker``.
    private static let arguments: [String: Value] = [argumentName: .string(argumentMarker)]

    // MARK: - Helpers

    /// The client spans of MCP calls in `context`.
    ///
    /// - Parameter context: The capture that holds the spans.
    /// - Returns: The spans, in the order of their end.
    private static func clientSpans(in context: TelemetryCapture.Context) -> [FinishedInMemorySpan] {
        context.spans.filter { $0.operationName == MultitoolTelemetry.SpanName.mcpClientCall.rawValue }
    }

    /// The attribute `key` of `span`.
    ///
    /// - Parameters:
    ///   - key: The attribute key.
    ///   - span: The span.
    /// - Returns: The value, or `nil` when the span has no value under `key`.
    private static func attribute(
        _ key: MultitoolTelemetry.AttributeKey, of span: FinishedInMemorySpan
    ) -> SpanAttribute? {
        span.attributes.get(key.rawValue)
    }

    /// Records a failure unless `span` has the error status, `outcome` and
    /// `errorKind`.
    ///
    /// - Parameters:
    ///   - span: The client span.
    ///   - outcome: The outcome that the span must have.
    ///   - errorKind: The error kind that the span must have.
    private static func expectFailure(
        of span: FinishedInMemorySpan, outcome: MultitoolTelemetry.OutcomeValue,
        errorKind: MultitoolTelemetry.ErrorKindValue
    ) {
        #expect(span.status?.code == .error)
        #expect(attribute(.outcome, of: span) == .string(outcome.rawValue))
        #expect(attribute(.errorKind, of: span) == .string(errorKind.rawValue))
    }

    /// Records a failure unless `span` has exactly one event named `name`.
    ///
    /// - Parameters:
    ///   - span: The client span.
    ///   - name: The name of the event.
    private static func expectOneEvent(on span: FinishedInMemorySpan, named name: MultitoolTelemetry.SpanEventName) {
        #expect(span.events.filter { $0.name == name.rawValue }.count == 1)
    }

    // MARK: - The client span and the traceparent

    @Test("a tools/call opens one client span, a child of the current span, and the request _meta carries its traceparent")
    func callCarriesTheTraceparentOfItsClientSpan() async throws {
        let scripted = await Self.scriptedServer(serving: [Self.answeringTool(named: Self.echoToolName, isError: false)])
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker, Self.resultMarker]) { context in
            let (server, wire) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, logger: context.logger)
            let result = try await context.tracer.withSpan(Self.parentSpanName) { _ in
                try await server.call(name: Self.echoToolName, arguments: Self.arguments)
            }

            let parent = try #require(context.spans.first { $0.operationName == Self.parentSpanName })
            let clients = Self.clientSpans(in: context)
            #expect(clients.count == 1)
            let client = try #require(clients.first)
            #expect(client.kind == .client)
            #expect(client.parentSpanID == parent.spanID)
            #expect(client.traceID == parent.traceID)

            let callMetas = await wire.sentMetas.filter { $0.method == CallTool.name }
            #expect(callMetas.count == 1)
            let meta = try #require(callMetas.first)
            let traceparent = try #require(meta.fields[SpanIdentity.traceparentField])
            #expect(traceparent.hasPrefix(Self.traceparentVersionPrefix))
            let identity = try #require(SpanIdentity(traceparent: traceparent))
            #expect(identity.traceID == client.traceID)
            #expect(identity.spanID == client.spanID)
            let progressToken = try #require(meta.fields[Self.progressTokenKey])

            #expect(Self.attribute(.serverName, of: client) == .string(Self.serverName))
            #expect(Self.attribute(.toolName, of: client) == .string(Self.echoToolName))
            #expect(Self.attribute(.requestID, of: client) == .string(progressToken))
            #expect(Self.attribute(.outcome, of: client) == .string(MultitoolTelemetry.OutcomeValue.succeeded.rawValue))
            #expect(Self.attribute(.contentCount, of: client) == .int64(1))
            let encodedContent = try JSONEncoder().encode(result.content)
            #expect(Self.attribute(.contentBytes, of: client) == .int64(Int64(encodedContent.count)))
            #expect(client.status?.code != .error)
        }
    }

    @Test("a tools/call writes one enter record with the trace id and the span id of its client span")
    func callWritesOneEnterRecord() async throws {
        let scripted = await Self.scriptedServer(serving: [Self.answeringTool(named: Self.echoToolName, isError: false)])
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker, Self.resultMarker]) { context in
            let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, logger: context.logger)
            _ = try await server.call(name: Self.echoToolName, arguments: Self.arguments)

            let client = try #require(Self.clientSpans(in: context).first)
            let enters = LogReadback.enterRecords(.mcpClientCall, in: context)
            #expect(enters.count == 1)
            let enter = try #require(enters.first)
            #expect(enter.metadataText(MultitoolTelemetry.AttributeKey.serverName) == Self.serverName)
            #expect(enter.metadataText(MultitoolTelemetry.AttributeKey.toolName) == Self.echoToolName)
            #expect(enter.metadata[LogReadback.traceIDKey] == "\(client.traceID)")
            #expect(enter.metadata[LogReadback.spanIDKey] == "\(client.spanID)")
        }
    }

    // MARK: - The error status

    @Test("a bare call that times out gives an error status on its client span")
    func timedOutCallGivesAnErrorStatus() async throws {
        let counter = CallCounter()
        let scripted = await Self.scriptedServer(serving: [Self.hangingTool(counting: counter)])
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, callTimeout: Self.shortCallTimeout, logger: context.logger)
            let result = try await server.call(name: Self.hangingToolName, arguments: Self.arguments)
            #expect(result.isError == true)

            let client = try #require(Self.clientSpans(in: context).first)
            Self.expectFailure(of: client, outcome: .timedOut, errorKind: .timeout)
        }
    }

    @Test("a tool that returns isError gives an error status on its client span")
    func isErrorResultGivesAnErrorStatus() async throws {
        let scripted = await Self.scriptedServer(serving: [
            Self.answeringTool(named: Self.failingToolName, isError: true)
        ])
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker, Self.resultMarker]) { context in
            let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
                to: scripted, name: Self.serverName, logger: context.logger)
            let result = try await server.call(name: Self.failingToolName, arguments: Self.arguments)
            #expect(result.isError == true)

            let client = try #require(Self.clientSpans(in: context).first)
            Self.expectFailure(of: client, outcome: .failed, errorKind: .isError)
            #expect(Self.attribute(.contentCount, of: client) == .int64(1))
        }
    }

    // MARK: - The span events

    @Test("a transport drop under a call records one span event on the client span, and an error status")
    func transportDropRecordsASpanEvent() async throws {
        let counter = CallCounter()
        let respawning = RespawningTransport.makeServingFreshScriptedServers {
            await Self.scriptedServer(serving: [Self.hangingTool(counting: counter)])
        }
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            let server = MCPServer(name: Self.serverName, logger: context.logger)
            try await server.connect(via: respawning, backoffPolicy: .default)
            let call = Task { try await server.call(name: Self.hangingToolName, arguments: Self.arguments) }
            try await TestPoll.waitUntil("the handler ran") { counter.count == Self.oneCallInFlight }
            await respawning.disconnect()
            await #expect(throws: MCPServerError.self) {
                _ = try await call.value
            }

            let client = try #require(Self.clientSpans(in: context).first)
            Self.expectOneEvent(on: client, named: .mcpTransportDropped)
            Self.expectFailure(of: client, outcome: .threw, errorKind: .transport)
        }
    }

    @Test("a reconnect under a call records one span event on the client span, and an error status")
    func reconnectRecordsASpanEvent() async throws {
        let counter = CallCounter()
        let respawning = RespawningTransport.makeServingFreshScriptedServers {
            await Self.scriptedServer(serving: [Self.hangingTool(counting: counter)])
        }
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            let server = MCPServer(name: Self.serverName, logger: context.logger)
            try await server.connect(via: respawning, backoffPolicy: .default)
            let call = Task { try await server.call(name: Self.hangingToolName, arguments: Self.arguments) }
            try await TestPoll.waitUntil("the handler ran") { counter.count == Self.oneCallInFlight }
            try await server.reconnect()
            await #expect(throws: (any Error).self) {
                _ = try await call.value
            }

            let client = try #require(Self.clientSpans(in: context).first)
            Self.expectOneEvent(on: client, named: .mcpReconnectStarted)
            #expect(client.status?.code == .error)
        }
    }
}
