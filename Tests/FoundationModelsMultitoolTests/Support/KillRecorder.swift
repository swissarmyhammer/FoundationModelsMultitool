// `KillRecorder` — a stand-in for the kill of a process group, which records
// each pid it gets and sends no signal.

import Darwin
import Synchronization

/// Records each kill that a runner sends, in place of `killpg`.
///
/// A test gives ``record(_:)`` to `ShellRunner.signalProcessGroup`. Thus the
/// test can count the kills, and no kill reaches a real process.
final class KillRecorder: Sendable {
    /// The pid of each recorded kill, in the order of the calls.
    private let pids = Mutex<[pid_t]>([])

    /// Records one kill of the group that `pid` leads.
    ///
    /// - Parameter pid: The pid that the kill names.
    func record(_ pid: pid_t) {
        pids.withLock { $0.append(pid) }
    }

    /// The count of the recorded kills.
    var count: Int {
        pids.withLock { $0.count }
    }
}
