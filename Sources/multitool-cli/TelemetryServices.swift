import Foundation
import Logging
import ServiceLifecycle

/// The export services of the OTLP backends that ``TelemetryBootstrap`` made,
/// and the lifecycle that runs them for the life of the command.
///
/// An OTLP exporter sends its records in batches, from the background work of
/// its service. A process exit does not flush a batch. Thus the last spans and
/// log records of a run are lost unless the services run while the command
/// runs, and then get a graceful shutdown, which flushes each exporter, before
/// the process exits.
///
/// The command returns its exit code on each normal end: a success, and an
/// answer that failed (`CLIRunner.ExitCode.answerFailed`, exit code 70) among
/// the others. Thus each of those ends goes through the flush.
///
/// A collector that is not there, or that never answers, must not hold the
/// process. Thus the shutdown has a time bound, ``shutdownBound``. When the
/// bound ends first, the process exits and the records that are not sent are
/// lost.
///
/// The bound is a race in this type, and not the
/// `maximumGracefulShutdownDuration` of swift-service-lifecycle. That setting
/// changes a slow shutdown into a cancellation, and its
/// `maximumCancellationDuration` changes a slow cancellation into a
/// `fatalError`, which would change the exit code of the run.
struct TelemetryServices: Sendable {
    /// The number of seconds in ``shutdownBound``.
    private static let shutdownBoundSeconds = 2

    /// The longest time the exporters get to flush after the command ends.
    private static let shutdownBound: Duration = .seconds(shutdownBoundSeconds)

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

    /// Runs `command` while the export services run, flushes the exporters,
    /// and then ends the process with the code that `command` returned.
    ///
    /// When there is no export service, this function runs `command` and
    /// exits.
    ///
    /// When there are export services, the process exits at the first of two
    /// events after `command` returns: the services finished their graceful
    /// shutdown, or ``shutdownBound`` ended. The exit occurs inside the task
    /// group, because a task group waits for all of its child tasks before it
    /// returns, and a service that does not stop must not hold the process.
    ///
    /// - Parameter command: The work of the process. It returns the exit code.
    func runThenExit(_ command: @Sendable () async -> Int32) async -> Never {
        guard !services.isEmpty else { exit(await command()) }
        let group = ServiceGroup(services: services, logger: Self.groupLogger)
        await withTaskGroup(of: Void.self, returning: Never.self) { tasks in
            tasks.addTask { try? await group.run() }
            let code = await command()
            await group.triggerGracefulShutdown()
            tasks.addTask { try? await Task.sleep(for: Self.shutdownBound) }
            _ = await tasks.next()
            exit(code)
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
