import InMemoryLogging
import InMemoryTracing
import TelemetryTestSupport
import Testing
import Tracing

@testable import FoundationModelsMultitool

/// Coverage for the spans of the calls that can suspend for a long time, and
/// for the "enter" log record that each of these spans writes when it starts.
///
/// A tracing backend exports a span only when the span ends. A call that hangs
/// never ends, thus its span never leaves the process. The "enter" record
/// leaves the process at once. Thus a hung call shows as an enter record with
/// no ended span. These cases prove that each call gives one span and one
/// enter record, that the spans nest, that a hung call leaves its enter record
/// and no ended span, and that a thrown error sets the error status.
///
/// Each case runs in a `TelemetryCapture`, and binds the logger of the capture
/// as the bound logger of the library. The interpreter dispatches each
/// `tools.*` call from its own thread, and a record from that thread cannot
/// reach the capture of the case in another way (see
/// `MultitoolTelemetry.boundLogger`).
@Suite("CallSpans")
struct CallSpanTests {
    // MARK: - Fixture content

    /// The city argument of a `tools.*` call. No span and no record may carry
    /// it.
    private static let argumentMarker = "qzvSpanArgumentMarker"

    /// The prompt of a selection session. No span and no record may carry it.
    private static let promptMarker = "qzvSpanPromptMarker"

    /// The task of a `searchTools` call. No span and no record may carry it.
    private static let taskMarker = "qzvSpanTaskMarker"

    /// The key of the W3C trace id in an enter record.
    private static let traceIDKey = "trace.id"

    /// The key of the W3C span id in an enter record.
    private static let spanIDKey = "span.id"

    // MARK: - Helpers

    /// The message of the enter record of the span named `spanName`.
    ///
    /// - Parameter spanName: The name of the span.
    /// - Returns: `enter <spanName>`.
    private static func enterMessage(_ spanName: MultitoolTelemetry.SpanName) -> String {
        "enter \(spanName.rawValue)"
    }

    /// The enter records of `context` for the span named `spanName`.
    ///
    /// - Parameters:
    ///   - spanName: The name of the span.
    ///   - context: The capture that holds the records.
    /// - Returns: The records, in the order of the calls.
    private static func enterRecords(
        _ spanName: MultitoolTelemetry.SpanName, in context: TelemetryCapture.Context
    ) -> [InMemoryLogHandler.Entry] {
        context.logRecords.filter { "\($0.message)" == enterMessage(spanName) }
    }

    /// The ended spans of `context` with the name `spanName`.
    ///
    /// - Parameters:
    ///   - spanName: The name of the span.
    ///   - context: The capture that holds the spans.
    /// - Returns: The spans, in the order of their end.
    private static func spans(
        _ spanName: MultitoolTelemetry.SpanName, in context: TelemetryCapture.Context
    ) -> [FinishedInMemorySpan] {
        context.spans.filter { $0.operationName == spanName.rawValue }
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

    /// The span attribute of an outcome.
    ///
    /// - Parameter outcome: The outcome.
    /// - Returns: The outcome as a string attribute.
    private static func outcomeAttribute(_ outcome: MultitoolTelemetry.OutcomeValue) -> SpanAttribute {
        .string(outcome.rawValue)
    }

    /// A `runCode` over the fixture tools of this suite.
    ///
    /// - Parameter gate: The gate that ``GatedCodeTool`` waits on.
    /// - Returns: The tool.
    /// - Throws: What `MultiTool.Builder.buildRegistry()` throws.
    private static func makeMultiTool(gate: ReleaseGate = ReleaseGate()) throws -> MultiTool {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .addTool(ThrowingTool())
            .addTool(GatedCodeTool(gate: gate))
            .buildRegistry()
        return MultiTool(registry: registry)
    }

    // MARK: - runCode and tools.*

    @Test("a runCode call that calls one tools.* verb gives a runCode span with one child span, and two enter records")
    func runCodeSpanHasOneChildDispatchSpan() async throws {
        let multiTool = try Self.makeMultiTool()
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            _ = try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                try await multiTool.call(
                    arguments: RunCodeArguments(
                        code: "return await tools.getTemperature({ city: '\(Self.argumentMarker)' });"))
            }

            let runCode = try #require(Self.spans(.runCode, in: context).first)
            let dispatches = Self.spans(.toolsDispatch, in: context)
            #expect(Self.spans(.runCode, in: context).count == 1)
            #expect(dispatches.count == 1)
            let dispatch = try #require(dispatches.first)
            #expect(dispatch.parentSpanID == runCode.spanID)
            #expect(dispatch.traceID == runCode.traceID)
            #expect(Self.attribute(.toolName, of: runCode) == .string(multiTool.name))
            #expect(Self.attribute(.toolName, of: dispatch) == "getTemperature")
            #expect(Self.attribute(.outcome, of: dispatch) == Self.outcomeAttribute(.succeeded))
            #expect(Self.attribute(.outcome, of: runCode) == Self.outcomeAttribute(.succeeded))

            let runCodeEnter = try #require(Self.enterRecords(.runCode, in: context).first)
            let dispatchEnter = try #require(Self.enterRecords(.toolsDispatch, in: context).first)
            #expect(Self.enterRecords(.runCode, in: context).count == 1)
            #expect(Self.enterRecords(.toolsDispatch, in: context).count == 1)
            let runCodeTraceID = try #require(runCodeEnter.metadata[Self.traceIDKey])
            #expect(dispatchEnter.metadata[Self.traceIDKey] == runCodeTraceID)
            let runCodeSpanID = try #require(runCodeEnter.metadata[Self.spanIDKey])
            let dispatchSpanID = try #require(dispatchEnter.metadata[Self.spanIDKey])
            #expect(dispatchSpanID != runCodeSpanID)
        }
    }

    @Test("a tools.* call that never returns gives an enter record and no ended span, and the parent is still open")
    func hungDispatchLeavesItsEnterRecordAndNoEndedSpan() async throws {
        let gate = ReleaseGate()
        let multiTool = try Self.makeMultiTool(gate: gate)
        try await TelemetryCapture.run(forbidding: []) { context in
            let run = Task {
                try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                    try await multiTool.call(arguments: RunCodeArguments(code: gatedCodeSnippet))
                }
            }
            try await TestPoll.waitUntil("the enter record of the gated tools.* call") {
                !Self.enterRecords(.toolsDispatch, in: context).isEmpty
            }

            #expect(Self.enterRecords(.runCode, in: context).count == 1)
            #expect(Self.spans(.toolsDispatch, in: context).isEmpty)
            #expect(Self.spans(.runCode, in: context).isEmpty)
            let open = context.tracer.activeSpans.map(\.operationName)
            #expect(open.contains(MultitoolTelemetry.SpanName.runCode.rawValue))
            #expect(open.contains(MultitoolTelemetry.SpanName.toolsDispatch.rawValue))

            await gate.release()
            _ = try await run.value
            #expect(Self.spans(.toolsDispatch, in: context).count == 1)
            #expect(Self.spans(.runCode, in: context).count == 1)
        }
    }

    @Test("a tools.* call that throws sets the error status on its span")
    func thrownErrorSetsTheErrorStatus() async throws {
        let multiTool = try Self.makeMultiTool()
        try await TelemetryCapture.run(forbidding: [Self.argumentMarker]) { context in
            _ = try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                try await multiTool.call(
                    arguments: RunCodeArguments(
                        code: "return await tools.throwingTool({ city: '\(Self.argumentMarker)' });"))
            }

            let dispatch = try #require(Self.spans(.toolsDispatch, in: context).first)
            #expect(dispatch.status?.code == .error)
            #expect(dispatch.errors.count == 1)
            #expect(Self.attribute(.outcome, of: dispatch) == Self.outcomeAttribute(.threw))
        }
    }

    // MARK: - searchTools

    @Test("a searchTools call gives a span with a search child and a sample child, and one enter record each")
    func searchToolsSpanHasSearchAndSampleChildren() async throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let searchTools = try SearchToolsTool(registry: registry, selection: nil)
        try await TelemetryCapture.run(forbidding: [Self.taskMarker]) { context in
            _ = try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                try await searchTools.call(arguments: SearchToolsArguments(task: Self.taskMarker))
            }

            let call = try #require(Self.spans(.searchTools, in: context).first)
            let search = try #require(Self.spans(.searchToolsSearch, in: context).first)
            let sample = try #require(Self.spans(.searchToolsSample, in: context).first)
            #expect(search.parentSpanID == call.spanID)
            #expect(sample.parentSpanID == call.spanID)
            #expect(Self.enterRecords(.searchTools, in: context).count == 1)
            #expect(Self.enterRecords(.searchToolsSearch, in: context).count == 1)
            #expect(Self.enterRecords(.searchToolsSample, in: context).count == 1)
        }
    }

    // MARK: - The selection session

    @Test("a traced session call gives one respond span and one enter record, and a thrown error sets the error status")
    func agentSessionRespondSpanRecordsTheError() async throws {
        // No scripted response, thus the first call throws.
        let session = TracedAgentSession(wrapped: ScriptedAgentSession([]), role: TracedAgentSession.selectionRole)
        try await TelemetryCapture.run(forbidding: [Self.promptMarker]) { context in
            await #expect(throws: ScriptedAgentSessionError.self) {
                try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                    try await session.respond(to: Self.promptMarker)
                }
            }

            let respond = try #require(Self.spans(.agentSessionRespond, in: context).first)
            #expect(Self.spans(.agentSessionRespond, in: context).count == 1)
            #expect(Self.enterRecords(.agentSessionRespond, in: context).count == 1)
            #expect(respond.status?.code == .error)
            #expect(Self.attribute(.sessionRole, of: respond) == .string(TracedAgentSession.selectionRole))
            #expect(Self.attribute(.promptCharacters, of: respond) == .int64(Int64(Self.promptMarker.count)))
            #expect(Self.attribute(.outcome, of: respond) == Self.outcomeAttribute(.threw))
        }
    }
}
