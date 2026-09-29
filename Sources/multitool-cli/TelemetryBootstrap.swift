import Foundation
import Logging
import MultitoolCLI
import OTel
import ServiceLifecycle

/// Bootstraps the telemetry backends of the `multitool-cli` process.
///
/// The design of 2026-09-28: only an executable links swift-otel and
/// bootstraps a backend, and the standard `OTEL_*` environment variables
/// configure it. An executable must always bootstrap logging. Standard output
/// of `multitool-cli` carries only the answers, thus no log handler of this
/// process writes to standard output.
///
/// `CLITelemetryBackend(environment:)` makes the choice:
///
/// - `.openTelemetry`: logs, traces and metrics go to the OTLP exporters of
///   swift-otel.
/// - `.standardError`: logging goes to `CLILogHandler`, which writes to
///   standard error. Tracing and metrics stay on their no-op defaults.
///
/// Logging is bootstrapped here, and not in `OTel.bootstrap`. `OTel.bootstrap`
/// bootstraps logs first and can then fail on metrics or traces, and a second
/// `LoggingSystem.bootstrap` after that stops the process. Thus this type
/// calls `LoggingSystem.bootstrap` one time on each path, and it gives
/// `OTel.bootstrap` a configuration with the logs off.
///
/// swift-otel gives back one export service for each backend it makes. This
/// type keeps them, and gives them back as ``TelemetryServices``, which runs
/// them for the life of the command and flushes them before the process exits.
enum TelemetryBootstrap {
    /// The lowest level of the swift-otel diagnostic messages that reach
    /// standard error. The default level, `info`, writes one line for each
    /// bootstrapped system on each run. `OTEL_LOG_LEVEL` can change it.
    private static let diagnosticLogLevel: OTel.Configuration.LogLevel = .warning

    /// The text that starts the line this type writes when a backend cannot
    /// be made.
    private static let failurePrefix = "multitool-cli: a telemetry backend is off"

    /// Bootstraps logging, tracing and metrics for this process.
    ///
    /// Call it one time, as the first statement of the process, before the
    /// first log record. swift-log stops the process on a second bootstrap.
    ///
    /// It reads the environment of the process, as swift-otel does for each
    /// `OTEL_*` variable, thus the choice here and the configuration there
    /// come from the same variables.
    ///
    /// - Returns: The export services of each backend that was made. The set
    ///   is empty when telemetry goes to standard error, or when no backend
    ///   could be made.
    static func bootstrap() -> TelemetryServices {
        switch CLITelemetryBackend(environment: ProcessInfo.processInfo.environment) {
        case .standardError:
            LoggingSystem.bootstrap(CLILogHandler.standardError)
            return TelemetryServices(services: [])
        case .openTelemetry:
            return bootstrapOpenTelemetry()
        }
    }

    /// Bootstraps the OTLP exporters for logs, traces and metrics.
    ///
    /// - Returns: The export services of each exporter that was made.
    private static func bootstrapOpenTelemetry() -> TelemetryServices {
        var configuration = OTel.Configuration.default
        configuration.diagnosticLogLevel = diagnosticLogLevel
        let logs = loggingBackend(configuration: configuration)
        LoggingSystem.bootstrap(logs.factory)
        let tracesAndMetrics = bootstrapTracingAndMetrics(configuration: configuration)
        return TelemetryServices(services: [logs.service, tracesAndMetrics].compactMap { $0 })
    }

    /// Makes the OTLP logs exporter.
    ///
    /// - Parameter configuration: The swift-otel configuration.
    /// - Returns: The log handler factory of the exporter and its export
    ///   service. When the exporter cannot be made, the factory of
    ///   `CLILogHandler`, which writes to standard error, and no service.
    private static func loggingBackend(
        configuration: OTel.Configuration
    ) -> (factory: @Sendable (String) -> any LogHandler, service: (any Service)?) {
        do {
            let backend = try OTel.makeLoggingBackend(configuration: configuration)
            return (backend.factory, backend.service)
        } catch {
            reportFailure(error)
            return (CLILogHandler.standardError, nil)
        }
    }

    /// Bootstraps the OTLP traces and metrics exporters.
    ///
    /// The logs are off in the configuration given to `OTel.bootstrap`,
    /// because ``bootstrapOpenTelemetry()`` already bootstrapped logging.
    ///
    /// - Parameter configuration: The swift-otel configuration.
    /// - Returns: The export service of the two exporters, or `nil` when they
    ///   cannot be made.
    private static func bootstrapTracingAndMetrics(configuration: OTel.Configuration) -> (any Service)? {
        var tracesAndMetrics = configuration
        tracesAndMetrics.logs.enabled = false
        do {
            return try OTel.bootstrap(configuration: tracesAndMetrics)
        } catch {
            reportFailure(error)
            return nil
        }
    }

    /// Writes one line to standard error that says a backend cannot be made.
    ///
    /// The run continues without that backend: telemetry must not change the
    /// outcome of a run.
    ///
    /// - Parameter error: The error that swift-otel gave.
    private static func reportFailure(_ error: any Error) {
        CLIRunner.standardErrorOutput("\(failurePrefix): \(error)")
    }
}
