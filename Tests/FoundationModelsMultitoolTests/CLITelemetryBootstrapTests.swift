import Foundation
import Logging
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolCLI
@testable import MultitoolTestSupport

/// Covers the telemetry choice of `multitool-cli` and the guard that keeps
/// each log line off standard output.
///
/// The executable target bootstraps the logging system one time, before the
/// first log record. This suite never calls `LoggingSystem.bootstrap`: the
/// test process bootstraps it one time, through `TelemetryCapture`, and a
/// second bootstrap stops the process. Thus the suite reads the two parts that
/// the bootstrap uses:
///
/// - the pure choice `CLITelemetryBackend(environment:)`, with an environment
///   that the test gives;
/// - the log handler of the path with no endpoint, `CLILogHandler`, which the
///   test binds as the logger of the library through
///   `MultitoolTelemetry.$boundLogger`.
///
/// Standard output carries only the answers of the CLI. A log line there would
/// mix with an answer, and a script that reads the answers would read the log
/// line as an answer.
@Suite("CLITelemetryBootstrap")
struct CLITelemetryBootstrapTests {
    /// The variable that turns the OTLP exporters on.
    private static let endpointVariable = "OTEL_EXPORTER_OTLP_ENDPOINT"

    /// The variable that turns the whole OpenTelemetry SDK off.
    private static let sdkDisabledVariable = "OTEL_SDK_DISABLED"

    /// An OTLP endpoint. No test sends a record to it.
    private static let endpoint = "http://localhost:4318"

    /// The label of the loggers that the tests make.
    private static let testLabel = "CLITelemetryBootstrapTests"

    /// A text that a test logs and then looks for in the captured lines.
    private static let loggedText = "a record of the test"

    // MARK: - The choice of the backend

    @Test("an environment with an OTLP endpoint chooses OpenTelemetry")
    func endpointChoosesOpenTelemetry() {
        let backend = CLITelemetryBackend(environment: [Self.endpointVariable: Self.endpoint])

        #expect(backend == .openTelemetry)
    }

    @Test("an environment with no OTEL variable chooses standard error")
    func noEndpointChoosesStandardError() {
        let backend = CLITelemetryBackend(environment: [:])

        #expect(backend == .standardError)
    }

    @Test("an empty OTLP endpoint chooses standard error")
    func emptyEndpointChoosesStandardError() {
        let backend = CLITelemetryBackend(environment: [Self.endpointVariable: ""])

        #expect(backend == .standardError)
    }

    @Test(
        "OTEL_SDK_DISABLED turns the endpoint off, in each case of the letters",
        arguments: ["true", "TRUE", "True"])
    func disabledSDKChoosesStandardError(disabledValue: String) {
        let backend = CLITelemetryBackend(environment: [
            Self.endpointVariable: Self.endpoint,
            Self.sdkDisabledVariable: disabledValue,
        ])

        #expect(backend == .standardError)
    }

    @Test("OTEL_SDK_DISABLED=false keeps the endpoint on")
    func enabledSDKChoosesOpenTelemetry() {
        let backend = CLITelemetryBackend(environment: [
            Self.endpointVariable: Self.endpoint,
            Self.sdkDisabledVariable: "false",
        ])

        #expect(backend == .openTelemetry)
    }

    // MARK: - The log handler of the path with no endpoint

    @Test("the log handler writes one line with the level, the label, the message and the metadata")
    func handlerWritesOneLine() {
        let errorOutput = OutputCollector()
        let logger = Logger(label: Self.testLabel) { label in
            CLILogHandler(label: label, errorOutput: errorOutput.append)
        }

        logger.warning("\(Self.loggedText)", metadata: ["key": "value"])

        #expect(errorOutput.lines == ["warning \(Self.testLabel): \(Self.loggedText) key=value"])
    }

    @Test("the log handler writes no record below its level")
    func handlerDropsRecordsBelowItsLevel() {
        let errorOutput = OutputCollector()
        let logger = Logger(label: Self.testLabel) { label in
            CLILogHandler(label: label, errorOutput: errorOutput.append)
        }

        logger.debug("\(Self.loggedText)")

        #expect(logger.logLevel == .info)
        #expect(errorOutput.lines.isEmpty, "lines were: \(errorOutput.lines)")
    }

    // MARK: - No log line reaches standard output

    @Test("a log line of the library goes to standard error and not to standard output")
    func libraryLogLineGoesToStandardError() async {
        let standardOutput = OutputCollector()
        let standardError = OutputCollector()
        let logger = Logger(label: MultitoolTelemetry.logLabel) { label in
            CLILogHandler(label: label, errorOutput: standardError.append)
        }
        let widened = MultitoolTelemetry.LogMessage.schemaWidened.rawValue

        let exitCode = await MultitoolTelemetry.$boundLogger.withValue(logger) {
            await CLIRunner.run(
                arguments: [],
                resolve: { _, _, _ in
                    // The stub resolver stands in for the session: the
                    // library renders a schema that it must widen, which logs
                    // a warning, and then the resolve fails before a model
                    // loads.
                    _ = try ToolAPIRenderer.render(
                        name: "hasShape",
                        description: "Has a shape.",
                        parameters: UnrenderableArgument.generationSchema)
                    throw CLITelemetryBootstrapTestsError.injectedResolveFailure
                },
                output: standardOutput.append,
                errorOutput: standardError.append)
        }

        #expect(exitCode == CLIRunner.ExitCode.unavailable)
        #expect(
            standardError.lines.contains { $0.contains(widened) },
            "standard error was: \(standardError.lines)")
        #expect(
            !standardOutput.lines.contains { $0.contains(widened) },
            "standard output was: \(standardOutput.lines)")
        #expect(
            standardOutput.lines.contains(CLIRunner.surfaceListingHeading),
            "standard output was: \(standardOutput.lines)")
    }
}

/// The errors that the stub resolvers of this suite throw.
private enum CLITelemetryBootstrapTestsError: Error {
    /// The resolve of the stub fails, thus the run stops before a model loads.
    case injectedResolveFailure
}
