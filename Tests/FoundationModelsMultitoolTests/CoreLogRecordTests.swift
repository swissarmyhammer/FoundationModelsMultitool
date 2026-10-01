import FoundationModels
import Logging
import TelemetryTestSupport
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the swift-log records of the core library files: `MultiTool`,
/// `JSCInterpreter` and `ToolAPIRenderer`.
///
/// Each case runs the code in a `TelemetryCapture` and reads the records back
/// from it. Each case asserts the level, the constant message, the logger label
/// and the metadata keys of a record. A `MultiTool` case reads the label of the
/// logger that it binds. A `JSCInterpreter` or `ToolAPIRenderer` case binds no
/// logger, thus it reads the label of the library. Each case gives the capture
/// the content of the fixture — the JS source, the tool argument, the error
/// text — as forbidden strings, so a record that carries that content fails
/// the case.
///
/// `SurfaceRefresherTests` covers the record of `SurfaceRefresher`, and
/// `UnknownToolHintTests` covers the `imaginedTool` record of `MultiTool`.
@Suite("CoreLogRecords")
struct CoreLogRecordTests {
    // MARK: - Fixture content

    /// The city argument of a `tools.*` call. No record may carry it.
    private static let argumentMarker = "qzvArgumentMarker"

    /// A string in the JS source of a snippet. No record may carry it.
    private static let sourceMarker = "qzvSourceMarker"

    /// The text of an error that a snippet throws. No record may carry it.
    private static let errorMarker = "qzvErrorMarker"

    /// A score out of the `1...10` range of `RangedTool`, so that the call
    /// fails its validation before the tool runs. No record may carry it.
    private static let outOfRangeScore = "987654"

    /// The name of the schema property that `UnrenderableArgument` widens.
    private static let widenedProperty = "shape"

    /// A `runCode` over the three fixture tools of this suite.
    ///
    /// - Returns: The tool.
    /// - Throws: What `MultiTool.Builder.buildRegistry()` throws.
    private static func makeMultiTool() throws -> MultiTool {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .addTool(RangedTool())
            .addTool(ThrowingTool())
            .buildRegistry()
        return MultiTool(registry: registry)
    }

    /// Runs `code` through a new `runCode` in a capture that forbids
    /// `forbidden`.
    ///
    /// The case binds the logger of the capture as the bound logger of the
    /// library. The interpreter dispatches each `tools.*` call from its own
    /// thread, and a record from that thread cannot reach the capture of the
    /// task of the case in another way (see
    /// `MultitoolTelemetry.boundLogger`).
    ///
    /// - Parameters:
    ///   - code: The JS source of the snippet.
    ///   - forbidden: The strings that no record may carry.
    /// - Returns: The log records of the capture.
    /// - Throws: What the build of the tool or the call throws.
    private static func records(
        runningSnippet code: String, forbidding forbidden: [String]
    ) async throws -> [TelemetryCapture.LogRecord] {
        let multiTool = try makeMultiTool()
        return try await TelemetryCapture.run(forbidding: forbidden) { context in
            _ = try await MultitoolTelemetry.$boundLogger.withValue(context.logger) {
                try await multiTool.call(arguments: RunCodeArguments(code: code))
            }
            return context.logRecords
        }
    }

    // MARK: - MultiTool

    @Test("a tools.* call logs its start and its end at the debug level, with the tool name and no argument")
    func toolsCallLogsItsStartAndEnd() async throws {
        let records = try await Self.records(
            runningSnippet: "return await tools.getTemperature({ city: '\(Self.argumentMarker)' });",
            forbidding: [Self.argumentMarker]
        )

        let started = try #require(LogReadback.records(.toolInvocationStarted, in: records).first)
        #expect(started.level == .debug)
        #expect(started.label == LogReadback.captureLoggerLabel)
        #expect(started.metadataText(MultitoolTelemetry.AttributeKey.toolName) == "getTemperature")

        let finished = try #require(LogReadback.records(.toolInvocationFinished, in: records).first)
        #expect(finished.level == .debug)
        #expect(finished.label == LogReadback.captureLoggerLabel)
        #expect(finished.metadataText(MultitoolTelemetry.AttributeKey.toolName) == "getTemperature")
        #expect(finished.metadataText(MultitoolTelemetry.LogMetadataKey.durationMilliseconds) != nil)
    }

    @Test("a tools.* call that fails its validation logs a warning with the tool name and the error type")
    func validationFailureLogsAWarning() async throws {
        let records = try await Self.records(
            runningSnippet: "return await tools.rangedTool({ score: \(Self.outOfRangeScore) });",
            forbidding: [Self.outOfRangeScore]
        )

        let failed = try #require(LogReadback.records(.toolArgumentValidationFailed, in: records).first)
        #expect(failed.level == .warning)
        #expect(failed.label == LogReadback.captureLoggerLabel)
        #expect(failed.metadataText(MultitoolTelemetry.AttributeKey.toolName) == "rangedTool")
        #expect(failed.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) == "ToolInvokerError")
        #expect(failed.metadataText(MultitoolTelemetry.LogMetadataKey.errorCode) != nil)
    }

    @Test("a tools.* call with an argument that is not an object logs a warning with the error type")
    func marshalingFailureLogsAWarning() async throws {
        let records = try await Self.records(
            runningSnippet: "return await tools.getTemperature('\(Self.argumentMarker)');",
            forbidding: [Self.argumentMarker]
        )

        let failed = try #require(LogReadback.records(.toolArgumentMarshalingFailed, in: records).first)
        #expect(failed.level == .warning)
        #expect(failed.label == LogReadback.captureLoggerLabel)
        #expect(failed.metadataText(MultitoolTelemetry.AttributeKey.toolName) == "getTemperature")
        #expect(failed.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) == "ArgumentMarshalerError")
    }

    @Test("a tool that throws logs an error with the error type, and not the text of the error")
    func toolErrorLogsAnError() async throws {
        // `ThrowingTool` puts its city argument into the text of its error.
        let records = try await Self.records(
            runningSnippet: "return await tools.throwingTool({ city: '\(Self.argumentMarker)' });",
            forbidding: [Self.argumentMarker]
        )

        let failed = try #require(LogReadback.records(.toolInvocationFailed, in: records).first)
        #expect(failed.level == .error)
        #expect(failed.label == LogReadback.captureLoggerLabel)
        #expect(failed.metadataText(MultitoolTelemetry.AttributeKey.toolName) == "throwingTool")
        #expect(failed.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) == "ThrowingToolError")
    }

    // MARK: - JSCInterpreter

    @Test("a snippet logs its start with its size and its end with its duration, and not its source")
    func snippetLogsItsStartAndEnd() async throws {
        let code = "return '\(Self.sourceMarker)'.length;"

        let records = try await TelemetryCapture.run(forbidding: [Self.sourceMarker]) { context in
            _ = try JSCInterpreter().run(code: code, installing: [])
            return context.logRecords
        }

        let started = try #require(LogReadback.records(.snippetStarted, in: records).first)
        #expect(started.level == .debug)
        #expect(started.label == LogReadback.libraryLoggerLabel)
        #expect(started.metadataText(MultitoolTelemetry.LogMetadataKey.characterCount) == "\(code.count)")

        let finished = try #require(LogReadback.records(.snippetFinished, in: records).first)
        #expect(finished.level == .debug)
        #expect(finished.label == LogReadback.libraryLoggerLabel)
        #expect(finished.metadataText(MultitoolTelemetry.LogMetadataKey.durationMilliseconds) != nil)
    }

    @Test("a snippet that throws logs its end with the error type, and not the text of the error")
    func throwingSnippetLogsItsEnd() async throws {
        let records = try await TelemetryCapture.run(forbidding: [Self.errorMarker]) { context in
            #expect(throws: InterpreterError.self) {
                try JSCInterpreter().run(code: "throw new Error('\(Self.errorMarker)');", installing: [])
            }
            return context.logRecords
        }

        let ended = try #require(LogReadback.records(.snippetEnded, in: records).first)
        #expect(ended.level == .debug)
        #expect(ended.label == LogReadback.libraryLoggerLabel)
        #expect(ended.metadataText(MultitoolTelemetry.LogMetadataKey.errorType) == "InterpreterError")
        #expect(ended.metadataText(MultitoolTelemetry.LogMetadataKey.durationMilliseconds) != nil)
        #expect(LogReadback.records(.snippetFinished, in: records).isEmpty)
    }

    // MARK: - ToolAPIRenderer

    @Test("a schema element that widens to any logs a warning through the default report")
    func wideningLogsAWarning() async throws {
        let records = try await TelemetryCapture.run(forbidding: []) { context in
            _ = try ToolAPIRenderer.render(
                name: "hasShape",
                description: "Has a shape.",
                parameters: UnrenderableArgument.generationSchema
            )
            return context.logRecords
        }

        let widened = try #require(LogReadback.records(.schemaWidened, in: records).first)
        #expect(widened.level == .warning)
        #expect(widened.label == LogReadback.libraryLoggerLabel)
        let detail = try #require(widened.metadataText(MultitoolTelemetry.LogMetadataKey.wideningDetail))
        #expect(detail.contains(Self.widenedProperty), "the detail was: \(detail)")
    }
}
