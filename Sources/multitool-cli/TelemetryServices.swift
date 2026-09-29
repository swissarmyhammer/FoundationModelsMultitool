import Logging
import ServiceLifecycle

/// The export services of the OTLP backends that ``TelemetryBootstrap`` made,
/// and the flush that stops them.
///
/// An OTLP exporter sends its records in batches, from the background work of
/// its service. A process exit does not flush a batch. Thus the services run
/// while the command runs, and the exit path of the process
/// (`CLIExitPath` of `MultitoolCLI`) calls the flush of ``start()`` before the
/// process exits. The flush is a graceful shutdown of the services, which
/// flushes each exporter. The exit path bounds the time of the flush.
struct TelemetryServices: Sendable {
    /// The label of the logger of the service group.
    private static let groupLoggerLabel = "multitool-cli.telemetry"

    /// The export services to run. The array is empty when no OTLP exporter
    /// was made.
    private let services: [any Service]

    /// Creates the lifecycle for a set of export services.
    ///
    /// - Parameter services: The export services to run. An empty array means
    ///   that no OTLP exporter was made.
    init(services: [any Service]) {
        self.services = services
    }

    /// Starts the export services, and gives the flush that stops them.
    ///
    /// - Returns: The flush: it triggers the graceful shutdown of the
    ///   services, and it returns when each service stopped. `nil` when there
    ///   is no export service: then there is nothing to flush, and the exit
    ///   path does not wait.
    func start() -> (@Sendable () async -> Void)? {
        guard !services.isEmpty else { return nil }
        let group = ServiceGroup(services: services, logger: Self.groupLogger)
        let running = Task { try? await group.run() }
        return {
            await group.triggerGracefulShutdown()
            await running.value
        }
    }

    /// The logger of the service group. It writes nothing.
    ///
    /// The group logs its own start and shutdown. Those records would go to
    /// the OTLP logs exporter that the group shuts down, and they tell a user
    /// of `multitool-cli` nothing about the run.
    private static var groupLogger: Logger {
        Logger(label: groupLoggerLabel) { _ in SwiftLogNoOpLogHandler() }
    }
}
