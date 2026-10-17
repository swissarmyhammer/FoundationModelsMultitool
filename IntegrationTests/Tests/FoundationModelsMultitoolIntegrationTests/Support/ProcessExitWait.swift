// `ProcessExitWait` — a wait on the exit of a process that this process does
// not reap, and the read of the processes of one process group.
//
// A copy of `Tests/FoundationModelsMultitoolTests/Support/ProcessExitWait.swift`
// of the root package. That file stands in the unit test target, and this
// package reaches the products of the root package only, thus this target
// keeps its own copy.
//
// A test that killed a process group must know that each process of the
// group ended. A grandchild is not a child of this process, thus this process
// cannot `waitpid` it: launchd reaps it, at a time this process does not
// control. A poll on the pid is a wait on time. This wait is an event in
// place of the poll: a kqueue process-exit source (`EVFILT_PROC`,
// `NOTE_EXIT`) of the kernel.

import Darwin
import Dispatch
import Synchronization

/// The wait on the exit of one process, the reading of the exit, and the read
/// of the processes of one process group.
enum ProcessExitWait {
    /// The queue on which each exit source calls its handler.
    private static let queue = DispatchQueue(label: "ProcessExitWait")

    /// The `p_stat` value of a zombie: the process exited and no one reaped
    /// it yet.
    private static let zombieStatus = Int32(SZOMB)

    /// The signal `kill` takes to ASK whether a pid is there. Signal 0 sends
    /// nothing.
    private static let existenceProbeSignal: Int32 = 0

    /// What `kill` answers when it failed.
    private static let killFailed: Int32 = -1

    /// Whether `pid` exited: the pid is gone, the kernel marks the process as
    /// exiting, or the pid is a zombie that waits for its parent to reap it.
    ///
    /// The exiting state is necessary. The kernel sends `NOTE_EXIT` while it
    /// sets `P_WEXIT` on the process, and it sets `SZOMB` only later. In that
    /// window a read of `p_stat` alone tells "live", although the exit event
    /// was already sent. A wait that reads in that window and then registers
    /// its source can miss the event.
    ///
    /// - Parameter pid: The pid to read.
    /// - Returns: `true` when the process exited or is exiting.
    static func hasExited(_ pid: pid_t) -> Bool {
        isGone(pid) || isExitingOrZombie(pid)
    }

    /// Whether `pid` names no live process and no zombie: `kill(pid, 0)`
    /// answers `ESRCH`.
    ///
    /// - Parameter pid: The pid to read.
    /// - Returns: `true` when the pid is gone.
    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, existenceProbeSignal) == killFailed && errno == ESRCH
    }

    /// Whether the kernel marks `pid` as exiting (`P_WEXIT` in `p_flag`) or
    /// holds it as a zombie (`SZOMB` in `p_stat`), read through `sysctl` with
    /// `CTL_KERN, KERN_PROC, KERN_PROC_PID`.
    ///
    /// - Parameter pid: The pid to read.
    /// - Returns: `true` when the process is exiting or is a zombie. `false`
    ///   when the pid is live, or when the kernel holds no such pid.
    static func isExitingOrZombie(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = name.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return false }
        return info.kp_proc.p_flag & P_WEXIT != 0 || Int32(info.kp_proc.p_stat) == zombieStatus
    }

    /// The pids of each process that the kernel holds in the process group
    /// `group`, read through `sysctl` with `CTL_KERN, KERN_PROC, KERN_PROC_PGRP`.
    ///
    /// - Parameter group: The identifier of the process group to read.
    /// - Returns: The pids. An empty list when the group holds no process, or
    ///   when the read fails.
    static func processes(inGroup group: pid_t) -> [pid_t] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, group]
        var size = 0
        let sized = name.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), nil, &size, nil, 0)
        }
        guard sized == 0, size > 0 else { return [] }
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        let read = name.withUnsafeMutableBufferPointer { buffer in
            entries.withUnsafeMutableBytes { bytes in
                sysctl(buffer.baseAddress, u_int(buffer.count), bytes.baseAddress, &size, nil, 0)
            }
        }
        guard read == 0 else { return [] }
        return entries.prefix(size / MemoryLayout<kinfo_proc>.stride).map(\.kp_proc.p_pid)
    }

    /// Waits until `pid` exited. Returns at once when it exited already.
    ///
    /// The wait registers a process-exit source for `pid`, resumes the source,
    /// and only then reads the pid again. Thus an exit that comes between the
    /// first reading and the registration is not lost: the second reading
    /// sees it. Each reading also counts a process in the exit window
    /// between `NOTE_EXIT` and `SZOMB` (see ``hasExited(_:)``). The source is
    /// cancelled when the wait ends.
    ///
    /// The end of the wait is the result: the wait ends only on the exit
    /// event of the kernel, or on a reading that shows the exit. A caller
    /// must not read the pid again after the wait. That second read can see
    /// the process in the exit window as live, or see a new process that
    /// took the pid again.
    ///
    /// A process that never exits, for example one that the kill missed,
    /// makes the wait last until the task of the caller is cancelled. A
    /// cancel ends the wait, also a cancel that came before the call. No
    /// other event can end it: the exit is the event under test.
    ///
    /// - Parameter pid: The pid to wait for.
    static func waitUntilGone(_ pid: pid_t) async {
        guard !hasExited(pid), !Task.isCancelled else { return }
        let ending = ExitWaitEnding()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
                source.setEventHandler { ending.end() }
                source.resume()
                ending.start(continuation, source: source)
                if hasExited(pid) {
                    ending.end()
                }
            }
        } onCancel: {
            ending.end()
        }
    }
}

/// The one end of one wait of ``ProcessExitWait/waitUntilGone(_:)``: it
/// resumes the waiter one time, and cancels the source. The exit event, a
/// reading that shows the exit, and a cancel of the task each end it.
private final class ExitWaitEnding: Sendable {
    /// Where the wait stands.
    private enum Phase {
        /// The waiter and the source are not stored yet.
        case starting

        /// The wait waits for its end.
        case waiting(continuation: CheckedContinuation<Void, Never>, source: any DispatchSourceProcess)

        /// The wait ended, or a cancel came before it was stored.
        case ended
    }

    /// Where the wait stands now.
    private let phase = Mutex(Phase.starting)

    /// Stores the waiter and the source, or ends them at once when an end
    /// came before.
    ///
    /// - Parameters:
    ///   - continuation: The waiter to resume.
    ///   - source: The resumed exit source to cancel.
    func start(_ continuation: CheckedContinuation<Void, Never>, source: any DispatchSourceProcess) {
        let endedBefore = phase.withLock { current -> Bool in
            guard case .starting = current else { return true }
            current = .waiting(continuation: continuation, source: source)
            return false
        }
        guard endedBefore else { return }
        source.cancel()
        continuation.resume()
    }

    /// Resumes the waiter and cancels the source. A second call does nothing.
    /// A call before ``start(_:source:)`` makes that start end at once.
    func end() {
        let taken = phase.withLock { current -> (CheckedContinuation<Void, Never>, any DispatchSourceProcess)? in
            defer { current = .ended }
            guard case .waiting(let continuation, let source) = current else { return nil }
            return (continuation, source)
        }
        guard case (let continuation, let source)? = taken else { return }
        source.cancel()
        continuation.resume()
    }
}
