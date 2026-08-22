// `SandboxPreflight` — the canary machinery behind the `preflight` of a
// confining `CommandSandbox`: the spawn that proves the wrapper accepts a
// profile, and the gate that keeps that proof from being bought again for each
// command.
//
// It stands apart from the confining implementation because none of it is
// Seatbelt Profile Language. `CanarySpawn` is "run this wrapper on these
// arguments and tell me how it ended", and `CanaryGate` is "do this one time at
// most". The sandbox gives the arguments, and the sandbox decides what a
// nonzero exit means.
//
// Why a canary is there at all: the shell capability reports the termination
// status of the COMMAND, thus a profile that fails to compile at spawn time
// looks, after the fact, the same as a command that ended with the same code.
// `sandbox-exec` refuses a profile with exit 65, and a command can end with 65
// for reasons of its own. The answer is not to guess from exit codes
// afterwards. The answer is to make the ambiguous case impossible to reach: run
// the same profile against `/usr/bin/true` first, and start nothing when that
// run fails.

import Subprocess
import Synchronization
import System

/// How a canary run ended: the exit code of the wrapper, and each byte it wrote
/// to standard error.
///
/// Deliberately not a `Bool`. When a canary fails, its standard error is the
/// one text that says WHY — `sandbox-exec: syntax error: expecting ')'` and its
/// relatives — and that text is what a caller shows to whoever must correct the
/// configuration.
struct CanaryResult: Sendable, Equatable {

    /// The exit code of the wrapper: `0` when the profile compiled and the
    /// canary ran, and a diagnostic code of the wrapper in each other case.
    ///
    /// A canary that a signal stopped reports `signalExitCodeBase` plus that
    /// signal, which is the convention of the shell. Thus that case stays apart
    /// from each exit code the wrapper produces on its own.
    let exitCode: Int32

    /// Each byte the wrapper wrote to standard error, empty when it wrote
    /// nothing.
    let stderr: String
}

/// Runs `executable` with `arguments`, and reports how the run ended.
///
/// A function, and not a call to `Subprocess.run` written in place, thus a test
/// can put a stand-in here and count the spawns, or answer with a failure it
/// wrote, and it needs no child process. `liveCanarySpawn` is the one
/// implementation that production uses.
typealias CanarySpawn = @Sendable (_ executable: String, _ arguments: [String]) async throws ->
    CanaryResult

/// The limit on the standard error a canary captures, in bytes.
///
/// The diagnostics of a wrapper are one short line. The limit is large enough
/// that no real message is cut, and small enough that a wrapper that goes wrong
/// cannot flood the memory. `Subprocess` throws instead of cutting when a
/// process goes past the limit, which fails closed: a canary nobody can read is
/// a canary that failed.
private let canaryStandardErrorLimit = 65_536

/// The number the shell adds to a signal to report a process that the signal
/// stopped.
///
/// `SIGKILL` is 9, thus a canary that `SIGKILL` stopped reports 137. Each exit
/// code a wrapper produces on its own stands below this number, thus the two
/// cases stay apart.
private let signalExitCodeBase: Int32 = 128

/// The `CanarySpawn` of production: a real child process, with its standard
/// output dropped and its standard error captured.
let liveCanarySpawn: CanarySpawn = { executable, arguments in
    let result = try await Subprocess.run(
        .path(FilePath(executable)),
        arguments: Arguments(arguments),
        input: .none,
        output: .discarded,
        error: .string(limit: canaryStandardErrorLimit)
    )
    let exitCode: Int32
    switch result.terminationStatus {
    case .exited(let code):
        exitCode = code
    case .signaled(let signal):
        exitCode = signalExitCodeBase + signal
    }
    return CanaryResult(exitCode: exitCode, stderr: result.standardError ?? "")
}

/// The latch that makes a canary that passed a one-time cost for each sandbox
/// that a host builds.
///
/// **A reference type on purpose.** A confining sandbox is a copyable
/// structure, and it is copied freely — a capability copies the whole runner,
/// the sandbox included, for each session it connects to events. `Mutex` is
/// `~Copyable`, thus it cannot be a stored property of such a structure at all.
/// A small class that holds the mutex answers both problems at one time.
///
/// **What one gate covers, exactly.** A gate is made together with the sandbox
/// that owns it, and each copy of that value shares it. Thus the canary costs
/// one spawn for each sandbox a host BUILDS, and for the copies of it — not one
/// for each copy, and not one for each command. Two sandboxes that a host built
/// apart hold two gates, and each one pays for a canary, also when the two
/// carry the same configuration.
///
/// A latch also outlives a later change to the configuration it was bought
/// under, because a host can change the options of a sandbox after a pass. That
/// is safe, and it is not a hole: what the canary proves is that the STATIC
/// profile template compiles, and that each `param` reference in it has one
/// emitted parameter to match it. Both sides come from the same options BY
/// COUNT at the time of the call, thus a wider or narrower set of roots cannot
/// break the property the canary proved, and a path value is never read as
/// profile source. Profile text that a caller substitutes WOULD defeat the
/// latch, and that is why such an override is a hook for tests alone, and not a
/// hook for a host.
///
/// Only a canary that passed latches. A failure is not remembered, thus a
/// configuration that becomes healthy — the wrapper binary restored, a profile
/// corrected — is picked up by the next call, and it is not poisoned for the
/// life of the process. It fails closed either way: each call that has not yet
/// seen a pass either runs the canary or throws.
final class CanaryGate: Sendable {

    /// The canary run each caller shares: `nil` before the first call and after
    /// a failure, and a settled task once one run has passed.
    ///
    /// A `Task`, and not a `Bool`, because the canary is `async` and a `Mutex`
    /// cannot stay locked across a suspension. To hold the task itself lets the
    /// first caller start the work under the lock, and lets each caller that
    /// arrives together with it wait on that same task. Thus "one time at most"
    /// holds also when the callers overlap, and not for calls one after the
    /// other alone.
    private let canaryRun = Mutex<Task<Void, any Error>?>(nil)

    /// Runs `canary`, unless a run before it already passed.
    ///
    /// The canary runs in an unstructured `Task` on purpose: to cancel the
    /// caller that happened to start it must not leave the gate holding a
    /// cancelled run that each later caller then waits on.
    ///
    /// - Parameter canary: The check to run one time at most. It throws to
    ///   report a failure, and this method throws that same error again.
    /// - Throws: What `canary` throws — to each caller that waits on that same
    ///   run, and not to the one that started it alone.
    func passOnce(_ canary: @escaping @Sendable () async throws -> Void) async throws {
        let run = canaryRun.withLock { stored -> Task<Void, any Error> in
            if let stored { return stored }
            let started = Task { try await canary() }
            stored = started
            return started
        }
        do {
            try await run.value
        } catch {
            // Clear this run only, and only while it is still the stored one: a
            // caller that arrived together with it can already have started a
            // new attempt.
            canaryRun.withLock { stored in
                if stored == run { stored = nil }
            }
            throw error
        }
    }
}
