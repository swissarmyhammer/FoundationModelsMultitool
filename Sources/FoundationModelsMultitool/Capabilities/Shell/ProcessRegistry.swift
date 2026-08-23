// `ProcessRegistry` — the table of the process groups that `ShellRunner`
// spawns, and the backstop that keeps one of them from leaking.
//
// eventplan.md § "Consolidation of the siblings" keeps the two registries of the
// system apart: this one holds the CHILD PROCESS GROUPS of each shell run, and
// the registry of MCP holds the server subprocesses. A server subprocess is
// infrastructure. It has the life of a session, it is never a run, and it never
// takes a completion token. Nothing of the run plane belongs here: the mailbox
// of Router holds the parked run, its canceler and its terminal event.
//
// It is a plain registry that a lock guards, and not an actor: `register` and
// `deregister` must be callable from an ordinary synchronous context — above all
// the `atexit` closure below, which can await nothing — thus a
// `Mutex<Set<pid_t>>` from `Synchronization` backs it. Nothing here is isolated
// to an actor, thus each member is reachable from any concurrency domain with no
// hop.
//
// `ProcessRegistry.global` is the instance of the whole process that a
// production `ShellRunner` takes by default. It is wired to a best-effort
// `atexit` sweep, which installs exactly one time, on the first read, and which
// kills each process group that is still alive at a normal exit of the process.
// A test must always make and give its own private `ProcessRegistry()` when it
// must read or sweep the state of a registry: Swift Testing runs the suites of
// one package together in one process, thus a sweep of the SHARED registry in
// the middle of a run could `killpg` a pid that a different, live suite owns. In
// practice `sweep` never reaches `.global` anywhere but the `atexit` closure
// below — this file is the one place that joins the two — thus that hazard
// cannot happen. The discipline of the private instance keeps it that way as the
// suite grows.

import Foundation
import Synchronization

/// A registry of the pids of live process-group leaders, which a lock guards.
///
/// `ShellRunner` registers the pid of a child here right after it starts, and it
/// deregisters the pid once its own teardown already killed the group. Thus in
/// ordinary operation this registry is a ledger of what is live, and it is empty
/// between runs. `sweep(_:)` is the backstop for whatever a NORMAL exit of the
/// process still finds registered. See the header of this file, and the doc
/// comment of `ProcessRegistry.global`, for the limits of that guarantee.
///
/// A production `ShellRunner` should take `ProcessRegistry.global` and should
/// not make an instance. A test should always make its own private instance —
/// see the header of this file.
final class ProcessRegistry: Sendable {

    /// The pids of the live process-group leaders. A lock guards them, and not
    /// an actor, thus a synchronous caller — the `atexit` closure this file
    /// installs — can register, deregister and sweep with no `await`.
    private let pids = Mutex<Set<pid_t>>([])

    /// Registers `pid` — a process-group leader, whose group id is its pid,
    /// which is how `ShellRunner` spawns a child — as live.
    ///
    /// - Parameter pid: The pid of the leader of the group.
    func register(_ pid: pid_t) {
        pids.withLock { _ = $0.insert(pid) }
    }

    /// Deregisters `pid`. It does nothing when the pid is not registered now —
    /// for example a second call, or a pid nothing ever registered.
    ///
    /// - Parameter pid: The pid of the leader of the group.
    func deregister(_ pid: pid_t) {
        pids.withLock { _ = $0.remove(pid) }
    }

    /// A snapshot of each pid that is registered now — what `sweep(_:)` kills,
    /// and what a test reads.
    var registeredPids: Set<pid_t> {
        pids.withLock { $0 }
    }
}

/// Sends `SIGKILL` to the process group of each pid that `registry` holds now.
///
/// The sweep takes the registry as a parameter, and it never names
/// `ProcessRegistry.global`, thus a test can run it against a private registry
/// that it owns with no risk of reaching a pid it does not own.
///
/// `killpg` on a pid that is already dead fails with `ESRCH`. The sweep passes
/// over that failure in silence — a registry that holds a child somebody already
/// reaped is the expected steady state, because the teardown of each run already
/// takes its own group down — and it goes on to the rest of the set. The sweep
/// deregisters nothing itself: it is a backstop of last resort, and it is not
/// part of the ordinary register and deregister life cycle.
///
/// - Parameter registry: The registry whose groups to kill.
func sweep(_ registry: ProcessRegistry) {
    for pid in registry.registeredPids {
        _ = killpg(pid, SIGKILL)
    }
}

/// The registry of the whole process that the `atexit` sweep below targets. Only
/// the installer immediately below reads it — see the doc comment of
/// `ProcessRegistry.global` for why nothing else should touch it.
private let globalProcessRegistry = ProcessRegistry()

/// Installs the `atexit` sweep of `globalProcessRegistry`.
///
/// Swift makes a top-level `let` lazily, safely across threads, and exactly one
/// time on the first read. Thus `ProcessRegistry.global` starts this installer
/// by reading `globalProcessRegistrySweepInstalled` below — this file needs no
/// lock of its own, and the closure installs exactly one time however many times
/// a caller reads `.global`.
///
/// The closure that goes to `atexit` can capture nothing, because a C function
/// pointer carries no captured context. Thus it names `globalProcessRegistry`
/// directly as a top-level value, and not a local it captured.
///
/// - Returns: `true`, always. The value exists only to make the top-level `let`
///   below run this function one time.
@discardableResult
private func installGlobalProcessRegistrySweep() -> Bool {
    atexit {
        sweep(globalProcessRegistry)
    }
    return true
}

/// Makes `installGlobalProcessRegistrySweep()` run exactly one time, the first
/// time anything reads `ProcessRegistry.global`.
private let globalProcessRegistrySweepInstalled = installGlobalProcessRegistrySweep()

extension ProcessRegistry {

    /// The registry of the whole process that a production `ShellRunner`
    /// registers into by default, with an `atexit` sweep behind it — installed
    /// exactly one time, on the first read of this property — that kills each
    /// process group that is still registered at a normal exit of the process.
    ///
    /// **The limit, said plainly:** `atexit` runs on a NORMAL exit of the
    /// process only — a return from `main`, or a call of `exit(_:)`. It does NOT
    /// run on `SIGKILL` and it does not run on a crash. Thus it narrows, and it
    /// does not replace, the teardown that `ShellRunner` runs itself on each
    /// run. That teardown is what guarantees the group of a spawned child dies
    /// on every ordinary exit path of a run — a normal end, a time limit, a
    /// cancel, or a thrown error — long before the process itself ever exits.
    /// This registry has something to sweep exactly when a run that the mailbox
    /// parked is still going as the process exits normally: the pid of such a
    /// run stays registered until the teardown of its body runs, thus a normal
    /// exit in the middle of a parked run is the gap the sweep closes.
    ///
    /// Never reach for this in a test: Swift Testing runs the suites of one
    /// package together in one process, thus a sweep of this shared registry
    /// could `killpg` a pid that a DIFFERENT, live suite owns. Make a private
    /// `ProcessRegistry()` instead.
    static var global: ProcessRegistry {
        _ = globalProcessRegistrySweepInstalled
        return globalProcessRegistry
    }
}
