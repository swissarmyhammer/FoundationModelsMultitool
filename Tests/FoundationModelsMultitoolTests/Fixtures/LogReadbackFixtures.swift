import Foundation
import OSLog

// MARK: - The one log-store read of this test target
//
// A line an `os.Logger` writes reaches the log store a little AFTER the call
// that wrote it, so a read taken at that instant is a race. The read itself is
// always the same three steps: open the store of this process, take a position
// at an instant, and keep the entries of this package's own subsystem.
//
// Those three steps stand here one time. A suite that reads a line back polls
// this reader through `TestPoll`, thus every suite reads the same store, the
// same subsystem and the same window, and no copy can drift from another.

/// The `os.Logger` subsystem every logger of this package is built with.
let multitoolLogSubsystem = "FoundationModelsMultitool"

/// The composed message of every line this process wrote under
/// ``multitoolLogSubsystem`` since `start`.
///
/// - Parameter start: The instant to read from. A line older than this one is
///   dropped.
/// - Returns: The messages, in emission order.
/// - Throws: What `OSLogStore` throws when it cannot be opened or read.
func multitoolLogMessages(since start: Date) throws -> [String] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let entries = try store.getEntries(at: store.position(date: start))
    return entries.compactMap { entry in
        guard let log = entry as? OSLogEntryLog, log.subsystem == multitoolLogSubsystem else {
            return nil
        }
        return log.composedMessage
    }
}
