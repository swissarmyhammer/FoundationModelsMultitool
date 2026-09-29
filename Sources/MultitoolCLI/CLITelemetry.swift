import Logging

/// The telemetry backend that the `multitool-cli` executable bootstraps.
///
/// The design of 2026-09-28: only an executable links swift-otel and
/// bootstraps a backend, and the standard `OTEL_*` environment variables
/// configure it. An executable must always bootstrap logging, because standard
/// output of `multitool-cli` carries only the answers. A log line there would
/// mix with an answer.
///
/// This type is the pure half of that bootstrap: it reads an environment and
/// gives the choice. The executable reads the environment of the process and
/// does the one `LoggingSystem.bootstrap`. A unit test gives an environment of
/// its own, and never bootstraps the logging system of the test process.
public enum CLITelemetryBackend: Equatable, Sendable {
    /// The OTLP exporters of swift-otel receive the logs, the spans and the
    /// metrics. The `OTEL_*` variables configure the exporters.
    case openTelemetry

    /// Each log record goes to standard error through ``CLILogHandler``.
    /// Tracing and metrics stay on their no-op defaults.
    case standardError

    /// The variable that turns the OTLP exporters on.
    static let endpointVariable = "OTEL_EXPORTER_OTLP_ENDPOINT"

    /// The variable that turns the whole OpenTelemetry SDK off.
    static let sdkDisabledVariable = "OTEL_SDK_DISABLED"

    /// The value of ``sdkDisabledVariable`` that turns the SDK off. The
    /// OpenTelemetry specification compares it without regard to the case of
    /// the letters.
    static let sdkDisabledValue = "true"

    /// Chooses the backend for an environment.
    ///
    /// - Parameter environment: The environment variables to read, for
    ///   example `ProcessInfo.processInfo.environment`.
    public init(environment: [String: String]) {
        guard let endpoint = environment[Self.endpointVariable], !endpoint.isEmpty else {
            self = .standardError
            return
        }
        let isDisabled = environment[Self.sdkDisabledVariable]?.lowercased() == Self.sdkDisabledValue
        self = isDisabled ? .standardError : .openTelemetry
    }
}

/// The log handler of `multitool-cli` when no OTLP endpoint is set: it writes
/// each record as one line to standard error.
///
/// swift-log has `StreamLogHandler.standardError`, but that type has no public
/// initializer that takes a sink. Thus a test cannot read what it writes. This
/// handler writes through a sink, and the default sink is
/// `CLIRunner.standardErrorOutput`, the same writer as the error line of a
/// failed answer. A test gives a collector in its place.
///
/// The line is `<level> <label>: <message>`, then each metadata pair as
/// `key=value`, sorted by key.
public struct CLILogHandler: LogHandler {
    /// The label of the logger that holds this handler.
    private let label: String

    /// The sink of each line.
    private let errorOutput: @Sendable (String) -> Void

    /// The metadata of the logger that holds this handler.
    public var metadata: Logger.Metadata = [:]

    /// The metadata provider of the logger that holds this handler.
    public var metadataProvider: Logger.MetadataProvider?

    /// The lowest level that this handler writes. The default is `info`, the
    /// default of swift-log.
    public var logLevel: Logger.Level = .info

    /// Makes a handler that writes to standard error.
    ///
    /// This is the factory that the executable gives to
    /// `LoggingSystem.bootstrap`.
    ///
    /// - Parameter label: The label of the logger.
    /// - Returns: A handler whose sink is `CLIRunner.standardErrorOutput`.
    public static func standardError(label: String) -> CLILogHandler {
        CLILogHandler(label: label, errorOutput: CLIRunner.standardErrorOutput)
    }

    /// Makes a handler that writes each line to `errorOutput`.
    ///
    /// - Parameters:
    ///   - label: The label of the logger.
    ///   - errorOutput: The sink of each line.
    init(label: String, errorOutput: @escaping @Sendable (String) -> Void) {
        self.label = label
        self.errorOutput = errorOutput
    }

    /// Reads or writes one metadata value of the logger.
    ///
    /// - Parameter key: The metadata key.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Writes `event` as one line to the sink.
    ///
    /// The metadata of the line merges three sources. A key of a later source
    /// replaces the same key of an earlier one: the metadata of the handler,
    /// then the metadata of the provider, then the metadata of the call.
    ///
    /// - Parameter event: The log record.
    public func log(event: LogEvent) {
        let merged = metadata
            .merging(metadataProvider?.get() ?? [:]) { _, provided in provided }
            .merging(event.metadata ?? [:]) { _, called in called }
        let pairs = merged.sorted { $0.key < $1.key }.map { " \($0.key)=\($0.value)" }
        errorOutput("\(event.level) \(label): \(event.message)\(pairs.joined())")
    }
}
