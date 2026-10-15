// `ProcessGroupKill` — the one right to kill the process group of one shell
// child. That right ends before the reap of the child.
//
// The child of a run leads its own process group, thus its pid is also the
// identifier of the group. While the child is not reaped, the kernel keeps
// the pid, also when the child is a zombie. After the reap the kernel can
// give the pid to a new process, and that process can lead a new group. A
// `killpg` with the old pid after the reap can thus kill an unrelated process.
//
// `Subprocess.run` reaps the child after the body closure returned. The body
// closes this value as its last step (`killAndClose()`), thus before the
// reap. Each other kill (`kill()`) — the canceler, the timer of a time limit —
// reads the state under the same lock and sends nothing after the close. The
// kill and the close hold the lock while they send, thus a kill that already
// started ends before the close ends, and so before the reap starts.

import Darwin
import Synchronization

/// The right to kill the process group of one child, until the body of its
/// run closes it.
final class ProcessGroupKill: Sendable {
    /// What sends the kill to the group that a pid leads.
    typealias Signal = @Sendable (pid_t) -> Void

    /// The kill of a real process group: `killpg(pid, SIGKILL)`. A group that
    /// is already dead gives a harmless `ESRCH`.
    static let killGroup: Signal = { pid in
        _ = killpg(pid, SIGKILL)
    }

    /// The pid of the child, which is the identifier of its process group.
    let pid: pid_t

    /// `true` until ``killAndClose()`` ran.
    private let isOpen = Mutex(true)

    /// What sends the kill.
    private let signal: Signal

    /// Makes the right to kill the group of `pid`.
    ///
    /// - Parameters:
    ///   - pid: The pid of the child, which leads its own process group.
    ///   - signal: What sends the kill. It is ``killGroup`` by default; a test
    ///     gives a recorder.
    init(pid: pid_t, signal: @escaping Signal = ProcessGroupKill.killGroup) {
        self.pid = pid
        self.signal = signal
    }

    /// Kills the group, when the body of the run did not close this value yet.
    ///
    /// - Returns: `true` when the kill went out, and `false` when the value
    ///   was closed, thus the child can be reaped and its pid can be in use by
    ///   an unrelated process.
    @discardableResult
    func kill() -> Bool {
        isOpen.withLock { open in
            guard open else { return false }
            signal(pid)
            return true
        }
    }

    /// Kills the group one last time, and closes this value. After this call
    /// no ``kill()`` sends anything.
    ///
    /// The body of the run calls this as its last step, before
    /// `Subprocess.run` reaps the child. A second call does nothing.
    func killAndClose() {
        isOpen.withLock { open in
            guard open else { return }
            signal(pid)
            open = false
        }
    }
}
