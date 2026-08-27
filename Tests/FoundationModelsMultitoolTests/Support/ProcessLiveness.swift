// `ProcessLiveness` — the two readings of one pid the subprocess suites
// share: whether the pid is gone, and whether it is alive.

import Foundation

/// The readings of a pid a test of a spawned subprocess takes.
enum ProcessLiveness {
    /// The signal `kill` takes to ASK whether a pid is there. Signal 0 sends
    /// nothing: `kill` performs the checks of a signal it is about to send
    /// and then sends none.
    private static let existenceProbeSignal: Int32 = 0

    /// What `kill` answers when it reached the pid.
    private static let killReachedProcess: Int32 = 0

    /// What `kill` answers when it failed.
    private static let killFailed: Int32 = -1

    /// Whether `pid` names no live process and no zombie: `kill(pid, 0)`
    /// answers `ESRCH`.
    ///
    /// `ESRCH` — and not just "signaled" — proves a reap and not merely a
    /// kill: a killed but unreaped (zombie) pid still answers
    /// `kill(pid, 0) == 0`, because its pid slot stays allocated until
    /// something calls `waitpid`.
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when the pid is gone.
    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, existenceProbeSignal) == killFailed && errno == ESRCH
    }

    /// Whether `pid` names a live process (or a zombie).
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when `kill(pid, 0)` succeeds.
    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, existenceProbeSignal) == killReachedProcess
    }
}
