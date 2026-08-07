import Foundation
import OSLog

@testable import FoundationModelsMultitool

/// One `imaginedTool` line read back out of the unified log and parsed into
/// the triple the synonym-mining use needs.
///
/// Parsing here is the other half of the contract `UnknownToolHint
/// .Resolution.logMessage` writes: the emitted line is only useful if a
/// later script can turn it back into `(imagined, suggested, tier)` without
/// regex archaeology, so the tests read it back through a parser rather
/// than string-matching the whole line.
struct ImaginedToolLogRecord: Equatable {
    /// The `tools.*` path the model invented, without its `tools.` prefix.
    let imagined: String

    /// Which ranking tier answered the guess — `UnknownToolHint
    /// .SuggestionTier`'s raw value.
    let tier: String

    /// The catalog paths the hint offered, in the order it offered them.
    let suggested: [String]
}

/// Reads back every `imaginedTool` line this process emitted since `start`,
/// waiting for the log store to catch up with the emitting call.
///
/// `os_log` hands an entry to the logging system asynchronously, so a read
/// taken immediately after the emitting call can legitimately see nothing
/// yet. Rather than sleeping for a fixed interval and hoping, this polls
/// until at least `minimumCount` records are visible or the deadline
/// passes, then returns whatever the store holds. Per-process log delivery
/// is ordered, so a caller that waits for a record it emitted *last* has
/// also waited for everything it emitted before that — which is what lets
/// the negative test assert an absence without a race.
///
/// - Parameters:
///   - start: the instant to read from; entries older than this are ignored.
///   - minimumCount: how many records to wait for before returning.
/// - Returns: every `imaginedTool` record in the window, in emission order.
/// - Throws: whatever `OSLogStore` throws when it cannot be opened or read.
func imaginedToolLogRecords(since start: Date, waitingFor minimumCount: Int) async throws
    -> [ImaginedToolLogRecord]
{
    let deadline = Date().addingTimeInterval(logReadbackTimeout)
    var records = try readImaginedToolLogRecords(since: start)
    while records.count < minimumCount, Date() < deadline {
        try await Task.sleep(for: .milliseconds(logReadbackPollInterval))
        records = try readImaginedToolLogRecords(since: start)
    }
    return records
}

/// How long `imaginedToolLogRecords(since:waitingFor:)` waits for the log
/// store to catch up before giving up and returning what it has.
///
/// Generous on purpose: a miss here would make a genuine emission look like
/// a missing one, and the wait ends as soon as the records arrive.
private let logReadbackTimeout: TimeInterval = 20

/// How long `imaginedToolLogRecords(since:waitingFor:)` sleeps between
/// reads of the log store, in milliseconds.
private let logReadbackPollInterval = 50

/// Reads the current contents of this process's log store, once.
///
/// - Parameter start: the instant to read from.
/// - Returns: every `imaginedTool` record the store holds in that window.
/// - Throws: whatever `OSLogStore` throws when it cannot be opened or read.
private func readImaginedToolLogRecords(since start: Date) throws -> [ImaginedToolLogRecord] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let entries = try store.getEntries(at: store.position(date: start))
    return entries.compactMap { entry in
        guard let log = entry as? OSLogEntryLog, log.subsystem == multitoolLogSubsystem else {
            return nil
        }
        return ImaginedToolLogRecord(parsing: log.composedMessage)
    }
}

/// The `os.Logger` subsystem every logger in this package is built with.
private let multitoolLogSubsystem = "FoundationModelsMultitool"

extension ImaginedToolLogRecord {
    /// Parses one `imaginedTool` line, or fails when `message` is some other
    /// log line.
    ///
    /// - Parameter message: one composed log message.
    fileprivate init?(parsing message: String) {
        let fields = message.split(separator: " ")
        guard fields.first.map(String.init) == UnknownToolHint.logPrefix else { return nil }

        var values: [Substring: Substring] = [:]
        for field in fields.dropFirst() {
            guard let separator = field.firstIndex(of: "=") else { continue }
            values[field[..<separator]] = field[field.index(after: separator)...]
        }
        guard let imagined = values["imagined"], let tier = values["tier"],
            let suggested = values["suggested"]
        else {
            return nil
        }

        self.init(
            imagined: String(imagined),
            tier: String(tier),
            suggested: Self.parseSuggestions(suggested)
        )
    }

    /// Parses the bracketed, comma-separated `suggested=` value.
    ///
    /// - Parameter value: the field's raw text, brackets included.
    /// - Returns: the suggested paths, empty for `[]`.
    private static func parseSuggestions(_ value: Substring) -> [String] {
        let inner = value.dropFirst().dropLast()
        guard !inner.isEmpty else { return [] }
        return inner.split(separator: ",").map(String.init)
    }
}
