import Foundation
import Logging

/// The helpers that each log call of the library target uses.
///
/// Each type of the library makes its logger with ``makeLogger()`` when it
/// logs, and not one time in a `static let`. swift-log gives a logger the
/// handler of the logging system at the time that the logger is made. A host,
/// or a test capture, can bootstrap the logging system after the library
/// loads. A logger that the library made before that time would keep the old
/// handler, and its records would not reach the host.
extension MultitoolTelemetry {
    /// The logger that ``makeLogger()`` gives, in place of a new logger, in
    /// the task that binds a value here. `nil` in each other task.
    ///
    /// This is the factory seam of the tests. A test binds the logger of its
    /// telemetry capture here. The capture of FoundationModelsExtras sends a
    /// record to the capture of the task that writes it, but a `runCode` run
    /// dispatches its `tools.*` calls from the thread of the interpreter,
    /// which has no task of the test. Thus `MultiTool` makes its logger in
    /// the task of the call, before the interpreter starts, and each
    /// `tools.*` record goes through that logger. A host binds nothing here.
    @TaskLocal static var boundLogger: Logger?

    /// Makes a new logger with the label of the library target, or gives the
    /// ``boundLogger`` of the current task.
    ///
    /// - Returns: The ``boundLogger`` when the current task binds one, or
    ///   else a new logger that writes through the handler that the logging
    ///   system has now.
    static func makeLogger() -> Logger {
        boundLogger ?? Logger(label: logLabel)
    }

    /// The metadata of an error: its type and its code.
    ///
    /// The metadata never holds the description of the error, because a
    /// description can carry content, for example a tool argument or the text
    /// of a JS exception.
    ///
    /// - Parameter error: The error.
    /// - Returns: The type name under ``LogMetadataKey/errorType`` and the
    ///   `NSError` code under ``LogMetadataKey/errorCode``.
    static func errorMetadata(of error: any Error) -> Logger.Metadata {
        [
            LogMetadataKey.errorType.rawValue: "\(type(of: error))",
            LogMetadataKey.errorCode.rawValue: "\((error as NSError).code)",
        ]
    }

    /// The metadata of the time from `start` to now.
    ///
    /// - Parameter start: The instant that the measured work started.
    /// - Returns: The whole milliseconds under
    ///   ``LogMetadataKey/durationMilliseconds``.
    static func durationMetadata(since start: ContinuousClock.Instant) -> Logger.Metadata {
        let milliseconds = start.duration(to: .now) / .milliseconds(1)
        return [LogMetadataKey.durationMilliseconds.rawValue: "\(Int(milliseconds.rounded()))"]
    }

    /// The metadata of the name of a tool.
    ///
    /// - Parameter name: The model-facing name of the tool.
    /// - Returns: The name under ``AttributeKey/toolName``.
    static func toolNameMetadata(_ name: String) -> Logger.Metadata {
        [AttributeKey.toolName.rawValue: "\(name)"]
    }
}

extension Logger {
    /// Writes one record with a constant message of the library target.
    ///
    /// - Parameters:
    ///   - message: The constant message of the record.
    ///   - level: The level of the record.
    ///   - metadata: The variable values of the record: names, ids, counts and
    ///     sizes only.
    func log(
        _ message: MultitoolTelemetry.LogMessage, level: Logger.Level, metadata: Logger.Metadata = [:]
    ) {
        log(level: level, "\(message.rawValue)", metadata: metadata)
    }
}
