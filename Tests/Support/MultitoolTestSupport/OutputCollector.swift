// `OutputCollector` — the one thread-safe collector for the lines that the CLI
// writes.
//
// `CLIRunner.run(...)` and the answer drains of `MultitoolCLI` write each line
// through an injectable `@Sendable (String) -> Void` closure. A test gives
// `append` as that closure and asserts on `lines`, and no line goes to real
// standard output. The unit test target and `CLISmokeTests` of
// `IntegrationTests/` both read it, thus it stands in the
// `MultitoolTestSupport` product and not in one test target.

import os

/// A thread-safe collector for the lines that an injectable output closure
/// writes.
///
/// `final class ... Sendable`: `append` is given as a `@Sendable` closure, and
/// it is called from concurrent contexts (the console-progress poller of
/// `CLIRunner` runs on a background `Task` beside the main call).
final class OutputCollector: Sendable {
    /// Every line appended so far, in append order.
    private let linesBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Creates an empty collector.
    init() {}

    /// Every line appended so far, in append order.
    var lines: [String] { linesBox.withLock { $0 } }

    /// Appends one line — the `output` parameter of the CLI.
    ///
    /// - Parameter line: the line to record.
    func append(_ line: String) {
        linesBox.withLock { $0.append(line) }
    }
}
