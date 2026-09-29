import FoundationModels
import InMemoryTracing
import Logging
import MCP
import MCPTestServer
import TelemetryTestSupport
import Testing
import Tracing

@testable import FoundationModelsMultitool

/// The one proof of the no-content rule of ``MultitoolTelemetry``: no span
/// attribute, span event, log message, log metadata value or metric dimension
/// carries JS source, tool arguments, tool output, the task of a
/// `searchTools` call or an MCP payload.
///
/// A span, a log record and a metric leave the process through the backend of
/// the host, and the library cannot know where that backend sends them. Thus
/// the rule is a contract, and this suite measures it.
///
/// The suite drives the work in one `TelemetryCapture` of the Extras
/// `TelemetryTestSupport` helper. Each input and each output of the work is a
/// unique marker string:
///
/// - a `runCode` call whose JS source, `tools.*` argument and `tools.*` return
///   value each hold a marker,
/// - a JS run that throws an error whose text holds a marker,
/// - a `searchTools` call whose task holds a marker,
/// - an MCP `tools/call` against a `ScriptedServer`, with a marker in its
///   arguments and in its result,
/// - an MCP `tools/call` that fails, with a marker in its arguments and in
///   its result.
///
/// The capture reads each span name and attribute, each log message and
/// metadata value, and each metric name and dimension. It records an issue for
/// each of them that holds a marker. The capture does not read span events,
/// thus this suite reads the name and the attributes of each span event
/// itself. No check here names one record. Thus a new span, log record or
/// metric of the library must obey the rule when it is added, and this file
/// needs no change.
///
/// The work binds the logger of the capture as the bound logger of the
/// library. The interpreter runs each `tools.*` call from its own thread, and
/// a `tools.*` record from that thread cannot go to the capture in a different
/// way (see `MultitoolTelemetry.boundLogger`).
@Suite("No span, log record or metric carries the content of the caller")
struct TelemetryContentSafetyTests {
    // MARK: - Fixture content

    /// A comment in the JS source of the snippet.
    private static let sourceMarker = "qzvSafetySourceMarker"

    /// The argument of the `tools.*` call of the snippet.
    private static let toolArgumentMarker = "qzvSafetyToolArgumentMarker"

    /// The return value of the `tools.*` call of the snippet.
    private static let toolReturnMarker = "qzvSafetyToolReturnMarker"

    /// The text of the error that a snippet throws.
    private static let errorMarker = "qzvSafetyErrorMarker"

    /// The task of the `searchTools` call.
    private static let searchTaskMarker = "qzvSafetySearchTaskMarker"

    /// The argument of each MCP `tools/call`.
    private static let mcpArgumentMarker = "qzvSafetyMCPArgumentMarker"

    /// The result text of the MCP tool that succeeds.
    private static let mcpResultMarker = "qzvSafetyMCPResultMarker"

    /// The result text of the MCP tool that fails.
    private static let mcpFailureMarker = "qzvSafetyMCPFailureMarker"

    /// Each marker. No telemetry record may hold one of them.
    private static let markers = [
        sourceMarker, toolArgumentMarker, toolReturnMarker, errorMarker, searchTaskMarker, mcpArgumentMarker,
        mcpResultMarker, mcpFailureMarker,
    ]

    /// The name of the MCP server.
    private static let serverName = "mcp-safety-server"

    /// The name of the MCP tool that succeeds.
    private static let echoToolName = "echo-tool"

    /// The name of the MCP tool that fails.
    private static let failingToolName = "failing-tool"

    /// The name of the argument of each MCP call.
    private static let mcpArgumentName = "city"

    /// The snippet that calls the marker tool. A comment in the source holds
    /// ``sourceMarker``.
    private static let markerSnippet = """
        // \(sourceMarker)
        return await tools.\(MarkerTool.callName)({ text: '\(toolArgumentMarker)' });
        """

    /// The snippet that throws an error whose text holds ``errorMarker``.
    private static let throwingSnippet = "throw new Error('\(errorMarker)');"

    // MARK: - The test

    @Test("no span, span event, log record or metric carries JS source, tool, search or MCP content")
    func noTelemetryCarriesTheContentOfTheCaller() async throws {
        let registry = try MultiTool.Builder().addTool(MarkerTool(output: Self.toolReturnMarker)).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let searchTools = try SearchToolsTool(registry: registry, selection: nil)
        let scripted = await Self.scriptedServer()
        try await TelemetryCapture.run(forbidding: Self.markers) { context in
            try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                try await Self.driveRunCode(multiTool)
                _ = try await searchTools.call(arguments: SearchToolsArguments(task: Self.searchTaskMarker))
                try await Self.driveMCPCalls(against: scripted, logger: context.logger)
            }

            let eventLeaks = Self.spanEventLeaks(in: context)
            #expect(eventLeaks.isEmpty, "\(eventLeaks)")
            Self.expectWorkWasMeasured(in: context)
        }
    }

    // MARK: - The work

    /// Runs the marker snippet and the throwing snippet through `multiTool`.
    ///
    /// - Parameter multiTool: The `runCode` tool.
    /// - Throws: What the `runCode` calls throw.
    private static func driveRunCode(_ multiTool: MultiTool) async throws {
        let rendered = try await multiTool.call(arguments: RunCodeArguments(code: markerSnippet))
        // The return value reaches the caller, thus the tool really ran.
        #expect(rendered.contains(toolReturnMarker))
        let failure = try await multiTool.call(arguments: RunCodeArguments(code: throwingSnippet))
        // The error text reaches the caller, thus the snippet really threw.
        #expect(failure.contains(errorMarker))
    }

    /// Calls the MCP tool that succeeds and the MCP tool that fails.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server that serves the two tools.
    ///   - logger: The logger of the MCP server.
    /// - Throws: What the connect and the calls throw.
    private static func driveMCPCalls(against scripted: ScriptedServer, logger: Logger) async throws {
        let (server, _) = try await MCPTestSupport.connectedRecordingMCPServer(
            to: scripted, name: serverName, logger: logger)
        let arguments: [String: Value] = [mcpArgumentName: .string(mcpArgumentMarker)]
        let echoed = try await server.call(name: echoToolName, arguments: arguments)
        #expect(echoed.isError != true)
        let failed = try await server.call(name: failingToolName, arguments: arguments)
        #expect(failed.isError == true)
    }

    // MARK: - Fixtures

    /// A scripted server that serves the MCP tool that succeeds and the MCP
    /// tool that fails.
    ///
    /// - Returns: The scripted server.
    private static func scriptedServer() async -> ScriptedServer {
        let scripted = ScriptedServer()
        await scripted.addTool(answeringTool(named: echoToolName, text: mcpResultMarker, isError: false))
        await scripted.addTool(answeringTool(named: failingToolName, text: mcpFailureMarker, isError: true))
        return scripted
    }

    /// An MCP tool that answers with one text block.
    ///
    /// - Parameters:
    ///   - name: The name of the tool.
    ///   - text: The text of the result.
    ///   - isError: The `isError` flag of the result.
    /// - Returns: The scripted tool.
    private static func answeringTool(named name: String, text: String, isError: Bool) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: name, description: "Answers with a text.", inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
        }
    }

    // MARK: - Checks

    /// The leaks of the span events of `context`: the name and each attribute
    /// of each event of each span that holds a marker.
    ///
    /// - Parameter context: The capture that holds the spans.
    /// - Returns: One leak for each place and each marker that the place holds.
    private static func spanEventLeaks(in context: TelemetryCapture.Context) -> [TelemetryLeak] {
        let places = context.spans.flatMap { span in
            span.events.flatMap { event in
                eventPlaces(of: event, on: span.operationName)
            }
        }
        return places.flatMap { place in
            markers.filter { place.description.contains($0) }.map { TelemetryLeak(place: place, forbidden: $0) }
        }
    }

    /// The places of one span event: its name, then each of its attributes.
    ///
    /// - Parameters:
    ///   - event: The span event.
    ///   - spanName: The name of the span of the event.
    /// - Returns: The places.
    private static func eventPlaces(of event: SpanEvent, on spanName: String) -> [TelemetryPlace] {
        let eventSpan = "\(spanName) event \(event.name)"
        let attributes = attributeTable(of: event.attributes).map { key, value in
            TelemetryPlace.spanAttribute(span: eventSpan, key: key, value: String(describing: value))
        }
        return [.spanName(eventSpan)] + attributes
    }

    /// The label of the stored dictionary in `SpanAttributes`.
    private static let storedAttributesLabel = "_attributes"

    /// The attributes of a span event as a dictionary.
    ///
    /// `SpanAttributes` is not a `Sequence`, and its only public walk is a
    /// closure. Thus this function reads the stored dictionary with a
    /// `Mirror`. The public `count` must be equal to the count of the
    /// dictionary. If swift-distributed-tracing changes its storage, the
    /// test fails and does not hide an attribute.
    ///
    /// - Parameter attributes: The attributes of the span event.
    /// - Returns: Each attribute, by its key.
    private static func attributeTable(of attributes: SpanAttributes) -> [String: SpanAttribute] {
        let stored = Mirror(reflecting: attributes).descendant(storedAttributesLabel)
        let table = stored as? [String: SpanAttribute] ?? [:]
        #expect(table.count == attributes.count, "the Mirror did not read the attributes of SpanAttributes")
        return table
    }

    /// Records a failure unless `context` holds the spans, the log records and
    /// the metrics of the work. A capture that measured nothing would find no
    /// leak, thus the suite first proves that the work reached the capture.
    ///
    /// - Parameter context: The capture of the work.
    private static func expectWorkWasMeasured(in context: TelemetryCapture.Context) {
        let spanNames = Set(context.spans.map(\.operationName))
        let expectedSpans: [MultitoolTelemetry.SpanName] = [.runCode, .toolsDispatch, .searchTools, .mcpClientCall]
        for span in expectedSpans {
            #expect(spanNames.contains(span.rawValue), "no span \(span.rawValue)")
        }
        let messages = Set(context.logRecords.map { "\($0.message)" })
        let expectedMessages: [MultitoolTelemetry.LogMessage] = [.toolInvocationFinished, .snippetEnded]
        for message in expectedMessages {
            #expect(messages.contains(message.rawValue), "no log record \(message.rawValue)")
        }
        let metricLabels = Set(context.metricRecords.map(\.label))
        let expectedMetrics: [MultitoolTelemetry.MetricName] = [.toolCalls, .interpreterRunDuration, .mcpServerErrors]
        for metric in expectedMetrics {
            #expect(metricLabels.contains(metric.rawValue), "no metric \(metric.rawValue)")
        }
    }
}

// MARK: - The marker tool

/// The arguments of ``MarkerTool``.
@Generable
struct MarkerToolArguments {
    /// A text that the tool does not read.
    @Guide(description: "a text.")
    var text: String
}

/// The output of ``MarkerTool``.
@Generable
struct MarkerToolOutput {
    /// The fixed reply of the tool.
    var reply: String
}

/// A `tools.*` tool that returns a fixed marker, so that its return value is
/// content that no telemetry record may hold. The type names the module of
/// `Tool`, because `MCP` also has a `Tool`.
struct MarkerTool: FoundationModels.Tool {
    /// The `tools.*` name of the tool.
    static let callName = "echoMarker"

    /// The `tools.*` name of the tool.
    let name = MarkerTool.callName

    /// The description of the tool.
    let description = "Returns a fixed reply."

    /// The reply of each call.
    let output: String

    /// Returns ``output``.
    ///
    /// - Parameter arguments: The arguments of the call. The tool does not
    ///   read them.
    /// - Returns: The output.
    func call(arguments: MarkerToolArguments) async throws -> MarkerToolOutput {
        MarkerToolOutput(reply: output)
    }
}
