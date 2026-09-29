import InMemoryLogging
import Logging
import TelemetryTestSupport

@testable import FoundationModelsMultitool

// MARK: - The one log read-back of this test target
//
// The library target logs through swift-log. A suite runs the code under test
// in a `TelemetryCapture` of FoundationModelsExtras, and the capture keeps each
// log record of the task of the suite in memory. The capture bootstraps the
// logging system one time for each process. Thus no code of this test target
// calls `LoggingSystem.bootstrap`.
//
// A record goes to the capture of the task that writes it, and a child task
// gets the capture of its parent task. Thus two suites that run in parallel
// do not see the records of each other. A record that the task of the suite
// writes is in the capture when the call that wrote it returns.
//
// The readers of the records stand here one time, so that each suite reads
// the records in the same way.

/// The readers of the log records that a `TelemetryCapture` keeps.
enum LogReadback {
    /// The records of `context` that carry `message`, in the order of the
    /// calls.
    ///
    /// - Parameters:
    ///   - message: The constant message of the records to keep.
    ///   - context: The capture that holds the records.
    /// - Returns: The records, in the order of the calls.
    static func records(
        _ message: MultitoolTelemetry.LogMessage, in context: TelemetryCapture.Context
    ) -> [InMemoryLogHandler.Entry] {
        records(message, in: context.logRecords)
    }

    /// The records of `records` that carry `message`, in the order of the
    /// calls.
    ///
    /// - Parameters:
    ///   - message: The constant message of the records to keep.
    ///   - records: The records to read, for example the records that a case
    ///     returned from its capture.
    /// - Returns: The records, in the order of the calls.
    static func records(
        _ message: MultitoolTelemetry.LogMessage, in records: [InMemoryLogHandler.Entry]
    ) -> [InMemoryLogHandler.Entry] {
        records.filter { "\($0.message)" == message.rawValue }
    }
}

extension InMemoryLogHandler.Entry {
    /// The metadata value of this record under `key`, as text.
    ///
    /// - Parameter key: The metadata key: a case of
    ///   `MultitoolTelemetry.AttributeKey` or of
    ///   `MultitoolTelemetry.LogMetadataKey`.
    /// - Returns: The text of the value, or `nil` when the record has no value
    ///   under `key`.
    func metadataText(_ key: some RawRepresentable<String>) -> String? {
        metadata[key.rawValue].map { "\($0)" }
    }
}
