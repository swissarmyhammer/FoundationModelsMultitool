import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `ProcessRegistry` and for the `sweep(_:)` backstop it
/// takes.
///
/// Each test here makes a PRIVATE `ProcessRegistry()`, and never
/// `ProcessRegistry.global`. Swift Testing runs the suites of one package
/// together in one process, thus a sweep of the shared registry could `killpg` a
/// pid that a different suite owns. See the doc comment of
/// `ProcessRegistry.global`.
@Suite("ShellProcessRegistryTests")
struct ShellProcessRegistryTests {

    /// A pid that names no process, for the tests of membership. It is far above
    /// the pid range of a normal system, thus no signal can reach a real
    /// process through it.
    private static let absentPid: pid_t = 424_242

    /// A second pid that names no process, for the test that deregisters a pid
    /// nothing registered.
    private static let neverRegisteredPid: pid_t = 999_999

    /// How long the child of a sweep test sleeps, in seconds. It is long enough
    /// that the child is certainly alive when the sweep runs.
    private static let liveChildSeconds = "60"

    /// How long the child that must already be dead sleeps, in seconds. Zero,
    /// thus the child ends at once and the test reaps it before the sweep.
    private static let deadChildSeconds = "0"

    /// The mask of the wait status that holds the number of the signal that
    /// stopped a child. `waitpid` puts the signal in the low seven bits.
    private static let waitStatusSignalMask: Int32 = 0x7f

    /// The failure of the spawn of the child that a sweep test uses.
    private enum SpawnError: Error {
        /// `posix_spawnattr_init` did not prepare the attributes.
        case attributesNotPrepared
        /// `posix_spawn` refused, and it gave this code.
        case spawnRefused(Int32)
    }

    /// Spawns a real, long `/bin/sleep` child in its OWN process group, thus the
    /// process-group id of the child is its pid.
    ///
    /// That is the shape `ShellRunner` spawns a command in
    /// (`POSIX_SPAWN_SETPGROUP`), written here at the level of `posix_spawn`.
    ///
    /// - Parameter seconds: How long the child sleeps.
    /// - Returns: The pid of the child, which is also its process-group id.
    /// - Throws: `SpawnError` when the child does not start.
    private func spawnKillableChild(seconds: String) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw SpawnError.attributesNotPrepared
        }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        let path = "/bin/sleep"
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), strdup(seconds), nil]
        defer { for case let argument? in argv { free(argument) } }

        var pid: pid_t = 0
        let code = posix_spawn(&pid, path, nil, &attributes, argv, environ)
        guard code == 0 else { throw SpawnError.spawnRefused(code) }
        return pid
    }

    /// Reaps `pid` and gives back the number of the signal that stopped it.
    ///
    /// The call blocks until the child ends, thus the test reads a certain
    /// answer and it races no timer.
    ///
    /// - Parameter pid: The child to reap.
    /// - Returns: The pid that `waitpid` reaped, and the signal that stopped the
    ///   child.
    private func reap(_ pid: pid_t) -> (reaped: pid_t, signal: Int32) {
        var status: Int32 = 0
        let reaped = waitpid(pid, &status, 0)
        return (reaped, status & Self.waitStatusSignalMask)
    }

    // MARK: - The register and deregister life cycle

    @Test("register then deregister tracks live membership")
    func registerThenDeregisterTracksLiveMembership() {
        let registry = ProcessRegistry()
        #expect(registry.registeredPids.isEmpty)

        registry.register(Self.absentPid)
        #expect(registry.registeredPids == [Self.absentPid])

        registry.deregister(Self.absentPid)
        #expect(registry.registeredPids.isEmpty)
    }

    @Test("deregistering a pid nothing registered does nothing")
    func deregisteringAnUnregisteredPidDoesNothing() {
        let registry = ProcessRegistry()
        registry.deregister(Self.neverRegisteredPid)
        #expect(registry.registeredPids.isEmpty)
    }

    // MARK: - sweep(_:) kills each group that is still registered

    /// The load-bearing test: `sweep(_:)` on a private registry that holds a
    /// live process-group leader kills it.
    @Test("sweep kills a live child in a private registry")
    func sweepKillsALiveChildInAPrivateRegistry() throws {
        let registry = ProcessRegistry()
        let pid = try spawnKillableChild(seconds: Self.liveChildSeconds)
        registry.register(pid)

        #expect(kill(pid, 0) == 0, "expected \(pid) to be alive before the sweep")

        sweep(registry)

        let outcome = reap(pid)
        #expect(outcome.reaped == pid)
        #expect(outcome.signal == SIGKILL)
    }

    // MARK: - A pid that is already gone

    /// A pid in the registry that is already dead must not stop the sweep: the
    /// rest of the registered set — a genuinely live pid here — still dies.
    @Test("sweep tolerates a pid that is already gone and still kills the live members")
    func sweepToleratesAnAlreadyDeadPidAndStillKillsOtherLiveMembers() throws {
        let registry = ProcessRegistry()

        let livePid = try spawnKillableChild(seconds: Self.liveChildSeconds)
        registry.register(livePid)

        // A pid that is already gone, registered beside it: the child ends at
        // once, and the test reaps it before the sweep runs. Thus the sweep
        // certainly meets a stale pid.
        let deadPid = try spawnKillableChild(seconds: Self.deadChildSeconds)
        _ = reap(deadPid)
        #expect(kill(deadPid, 0) == -1 && errno == ESRCH, "expected \(deadPid) to be gone")
        registry.register(deadPid)

        sweep(registry)

        let outcome = reap(livePid)
        #expect(outcome.reaped == livePid)
        #expect(outcome.signal == SIGKILL)
    }
}
