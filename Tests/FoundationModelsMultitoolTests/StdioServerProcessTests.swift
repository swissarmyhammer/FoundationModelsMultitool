import Foundation
import FoundationModelsExtras
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `StdioServerProcess` — real children, spawned in their
/// own process group, registered into a `ProcessRegistry`, and torn down by
/// each of the four teardown paths the header of `StdioServerProcess.swift`
/// names.
///
/// A port of `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/StdioServerProcessTests.swift`.
/// The registry assertions of the source went against its own private
/// `ProcessRegistry`; here they go against the shared
/// `FoundationModelsExtras.ProcessRegistry`, which this package takes in place
/// of a copy.
///
/// **Four cases of the source are not here.** Each one connects an
/// `MCPServer` over the vended transport, and two of them also spawn the
/// `mcp-test-server` executable. They wait for the tasks that port those two
/// pieces, and they are listed here so that nothing is lost in silence:
///
/// - `respawnFailingToSpawnDoesNotBurnBackoffAttemptsWhenUsedAsMCPServerFactory`
///   — needs `MCPServer`, `BackoffPolicy` and `ManualClock` (task ^832pg8r).
/// - `respawnVendsAWorkingTransportThatCompletesAnMCPHandshakeAndToolCall`
///   — needs `MCPServer` and the test server (tasks ^832pg8r and ^gqrtxxy).
/// - `nameFlowsIntoServerIdentityOnceConnected` — the same two.
/// - `killingTheChildExternallySurfacesAsConnectionLossAndReconnects` — the
///   same two.
///
/// Each test constructs its own PRIVATE registry, and never `.global`, so a
/// group-kill cannot reach a process another suite owns. One test reads
/// `.global` and sweeps nothing: it proves the public initializer registers
/// there. The suite runs `.serialized`, thus the leak check each test ends
/// with — `sharedRegistry` empty — can never race a sibling still in flight.
/// That shared registry, checked empty at the end of every test, is the "no
/// stray pid survives the suite" coverage: a pid one test leaves behind fails
/// the NEXT test at its own final check.
@Suite(.serialized)
struct StdioServerProcessTests {
    /// Shared across every test of this suite — see the type-level doc for
    /// why one shared registry, asserted empty at the end of every test,
    /// proves more than "this one test cleaned up after itself."
    private static let sharedRegistry = ProcessRegistry()

    /// The absolute path of the long-lived child most tests spawn.
    private static let sleepCommand = "/bin/sleep"

    /// The arguments of that child: a sleep long enough to outlive any test.
    private static let sleepArguments = ["60"]

    /// The absolute path of the shell the tests that need a script spawn.
    private static let shellCommand = "/bin/sh"

    /// The flag that makes the shell read its script from the next argument.
    private static let shellScriptFlag = "-c"

    /// A well-formed (absolute) path that no file system holds, so that
    /// `posix_spawn` itself fails.
    private static let absentCommand = "/nonexistent/binary-that-does-not-exist"

    /// A command that is not an absolute path, which the initializer refuses.
    private static let relativeCommand = "sleep"

    /// How many children the group-kill script forks: two backgrounded
    /// `sleep`s.
    private static let forkedChildCount = 2

    /// How many times the leak test makes a spawn fail.
    private static let failedSpawnCount = 50

    /// How many file descriptors one spawn creates before `posix_spawn` runs:
    /// the two ends of the stdin pipe, and the two ends of the stdout pipe.
    private static let pipeFdsPerSpawn = 4

    /// Confirms `sharedRegistry` holds nothing — called at the end of every
    /// test in this suite.
    private static func confirmNoLeaks() {
        #expect(Self.sharedRegistry.registeredPids.isEmpty)
    }

    /// A `StdioServerProcess` over `sleepCommand`, registered into
    /// `sharedRegistry`.
    ///
    /// - Parameter name: The server name of the process.
    /// - Returns: The process, not yet spawned.
    /// - Throws: What `StdioServerProcess.init` throws.
    private static func makeSleeper(named name: String) throws -> StdioServerProcess {
        try StdioServerProcess(
            command: sleepCommand, args: sleepArguments, name: name, registry: sharedRegistry)
    }

    /// Whether `pid` names no live process and no zombie: `kill(pid, 0)`
    /// answers `ESRCH`.
    ///
    /// `ESRCH` — and not just "signaled" — proves a reap and not merely a kill:
    /// a killed but unreaped (zombie) pid still answers `kill(pid, 0) == 0`,
    /// because its pid slot stays allocated until something calls `waitpid`.
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when the pid is gone.
    private static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    /// Whether `pid` names a live process (or a zombie).
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when `kill(pid, 0)` succeeds.
    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - Absolute-path requirement

    @Test func initRejectsANonAbsoluteCommand() {
        #expect(throws: StdioServerProcess.StdioServerProcessError.self) {
            _ = try StdioServerProcess(
                command: Self.relativeCommand, args: Self.sleepArguments, name: "relative-path-test",
                registry: Self.sharedRegistry)
        }
    }

    @Test func initAcceptsAnAbsoluteCommand() throws {
        let stdio = try Self.makeSleeper(named: "absolute-path-test")
        #expect(stdio.command == Self.sleepCommand)
        Self.confirmNoLeaks()
    }

    // MARK: - A failed spawn attempt does not leak the pipe fds it created

    /// `respawn()` against a well-formed but absent executable must fail with
    /// `spawnFailed` — which proves the test reaches the failure path of
    /// `posix_spawn` itself — and must not leak the stdin/stdout pipe fds
    /// that the spawn created before that call failed.
    ///
    /// The fd count is process-wide, and the suites of this target run in
    /// parallel: another suite can open a descriptor for good between the two
    /// readings, so an exact comparison is a race. The spawn fails
    /// `failedSpawnCount` times instead, and the test asserts that the count
    /// grew by less than the leak those spawns would cause together. A leak
    /// is `pipeFdsPerSpawn` descriptors on every attempt, and no sibling
    /// suite opens that many in the same instant.
    @Test func respawnFailingToSpawnDoesNotLeakPipeFileDescriptors() async throws {
        let stdio = try StdioServerProcess(
            command: Self.absentCommand, name: "spawn-failure-test", registry: Self.sharedRegistry)

        let before = Self.openFileDescriptorCount()
        for _ in 0..<Self.failedSpawnCount {
            await #expect(throws: StdioServerProcess.StdioServerProcessError.self) {
                _ = try await stdio.respawn()
            }
        }
        let growth = Self.openFileDescriptorCount() - before

        #expect(
            growth < Self.pipeFdsPerSpawn * Self.failedSpawnCount,
            "expected no file descriptors leaked by a failed spawn attempt; the count grew by \(growth)")
        Self.confirmNoLeaks()
    }

    /// `spawnFailed` must name the offending path, thus a host can say WHICH
    /// server is misconfigured.
    @Test func respawnFailingToSpawnNamesTheOffendingCommandPath() async throws {
        let stdio = try StdioServerProcess(
            command: Self.absentCommand, name: "spawn-failure-naming-test", registry: Self.sharedRegistry)

        do {
            _ = try await stdio.respawn()
            Issue.record("expected respawn() to throw")
        } catch let error as StdioServerProcess.StdioServerProcessError {
            guard case .spawnFailed(let command, _) = error else {
                Issue.record("expected .spawnFailed, got \(error)")
                return
            }
            #expect(command == Self.absentCommand)
            #expect(error.description.contains(Self.absentCommand))
        }
        Self.confirmNoLeaks()
    }

    /// A pure classification test, with no spawn: `commandNotAbsolute` and
    /// `spawnFailed` are permanent (a bad path never spawns, however often it
    /// is retried), but `pipeCreationFailed` stays retryable — fd exhaustion
    /// in this process is plausibly transient.
    @Test func stdioServerProcessErrorClassifiesOnlyPathFailuresAsNonRetryable() {
        #expect(StdioServerProcess.StdioServerProcessError.commandNotAbsolute(Self.relativeCommand).isNonRetryable)
        #expect(
            StdioServerProcess.StdioServerProcessError.spawnFailed(command: Self.absentCommand, errno: ENOENT)
                .isNonRetryable)
        #expect(!StdioServerProcess.StdioServerProcessError.pipeCreationFailed(errno: EMFILE).isNonRetryable)
    }

    // MARK: - respawn() spawns in its own process group and registers the pid

    @Test func respawnSpawnsInItsOwnProcessGroupAndRegistersThePid() async throws {
        let stdio = try Self.makeSleeper(named: "own-group-test")
        _ = try await stdio.respawn()

        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        // Alive, and its own process-group leader (pgid == pid) — the shape
        // every group-kill in this suite depends on.
        #expect(Self.isAlive(pid))
        #expect(getpgid(pid) == pid)
        #expect(Self.sharedRegistry.registeredPids.contains(pid))

        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    /// The public initializer registers into `ProcessRegistry.global`, thus
    /// the `atexit` sweep behind it reaches a server a host forgot. This test
    /// reads the global registry and sweeps nothing.
    @Test func publicInitRegistersIntoTheGlobalRegistryWhileTheProcessRuns() async throws {
        let stdio = try StdioServerProcess(
            command: Self.sleepCommand, args: Self.sleepArguments, name: "global-registry-test")
        _ = try await stdio.respawn()

        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        #expect(ProcessRegistry.global.registeredPids.contains(pid))

        await stdio.shutdown()

        #expect(!ProcessRegistry.global.registeredPids.contains(pid))
        #expect(Self.isGone(pid))
    }

    // MARK: - Explicit shutdown group-kills and reaps, asserted by pid

    @Test func shutdownGroupKillsAndReapsAssertedByPid() async throws {
        let stdio = try Self.makeSleeper(named: "shutdown-test")
        _ = try await stdio.respawn()
        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        #expect(Self.isAlive(pid))

        await stdio.shutdown()

        #expect(Self.isGone(pid))
        #expect(!Self.sharedRegistry.registeredPids.contains(pid))
        Self.confirmNoLeaks()
    }

    // MARK: - respawn() tears down whatever it was fronting before spawning fresh

    @Test func respawnTerminatesAndReapsThePreviousProcessBeforeSpawningAFreshOne() async throws {
        let stdio = try Self.makeSleeper(named: "respawn-test")
        _ = try await stdio.respawn()
        guard let firstPid = stdio.currentPid else {
            Issue.record("expected first respawn() to record a pid")
            return
        }
        #expect(Self.isAlive(firstPid))

        _ = try await stdio.respawn()
        guard let secondPid = stdio.currentPid else {
            Issue.record("expected second respawn() to record a pid")
            return
        }
        #expect(secondPid != firstPid)
        #expect(Self.isGone(firstPid))
        #expect(Self.isAlive(secondPid))
        #expect(!Self.sharedRegistry.registeredPids.contains(firstPid))
        #expect(Self.sharedRegistry.registeredPids.contains(secondPid))

        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    // MARK: - Concurrent respawn() calls never orphan the losing pid

    /// Two `respawn()` calls on one instance can run at the same time — a
    /// connect attempt that a timeout abandoned is not cancelled, so a retry
    /// can spawn beside it. Whichever `recordSpawn` runs second must not
    /// overwrite the first pid in silence: that would leave a live child
    /// registered but unreachable by every teardown path of the type.
    @Test func concurrentRespawnCallsNeverOrphanTheLosingPid() async throws {
        let stdio = try Self.makeSleeper(named: "concurrent-respawn-test")

        async let first = stdio.respawn()
        async let second = stdio.respawn()
        _ = try await (first, second)

        guard let survivingPid = stdio.currentPid else {
            Issue.record("expected one of the two concurrent respawn() calls to leave a pid recorded")
            return
        }
        // Exactly one process may stay alive and registered — the one that
        // lost the race must be torn down, not orphaned.
        #expect(Self.isAlive(survivingPid))
        #expect(Self.sharedRegistry.registeredPids == [survivingPid])

        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    // MARK: - Process-group kill also terminates a child the spawned process forked

    /// A server that forks a child of its own must have that child killed too
    /// when this package tears the server down — the reason the spawn goes
    /// into its own process group instead of a kill of the one known pid.
    ///
    /// The script prints the pid of each backgrounded `sleep`, so the test
    /// asserts by pid and not by a count of a process listing.
    @Test func groupKillAlsoTerminatesAChildTheSpawnedProcessForkedItself() async throws {
        let stdio = try StdioServerProcess(
            command: Self.shellCommand,
            args: [Self.shellScriptFlag, "sleep 60 & echo $!; sleep 60 & echo $!; wait"],
            name: "group-kill-test",
            registry: Self.sharedRegistry
        )
        let transport = try await stdio.respawn()
        try await transport.connect()
        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }

        let childPids = try await Self.readPids(count: Self.forkedChildCount, from: transport)
        #expect(childPids.count == Self.forkedChildCount)
        for child in childPids {
            #expect(Self.isAlive(child))
            #expect(getpgid(child) == pid)
        }

        await stdio.shutdown()

        // A killed grandchild is reaped by the system, not by this process,
        // so its slot goes away a moment after the kill.
        for child in childPids {
            let gone = await TestPoll.holds { Self.isGone(child) }
            #expect(gone, "expected the forked child \(child) to die with its process group")
        }
        #expect(Self.isGone(pid))
        Self.confirmNoLeaks()
    }

    // MARK: - Connection teardown (the vended transport's disconnect()) also group-kills and reaps

    @Test func disconnectingTheVendedTransportGroupKillsAndReapsTheProcess() async throws {
        let stdio = try Self.makeSleeper(named: "connection-teardown-test")
        let transport = try await stdio.respawn()
        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        #expect(Self.isAlive(pid))

        // What a host's disconnect of the server built over this transport
        // reaches, with no explicit `stdio.shutdown()` call at all.
        await transport.disconnect()

        #expect(Self.isGone(pid))
        #expect(!Self.sharedRegistry.registeredPids.contains(pid))
        Self.confirmNoLeaks()
    }

    // MARK: - DisposableTransport conformance: dispose() reaps a never-connected spawn

    /// A `respawn()` that lost the race against a newer connect attempt has
    /// already spawned a real child by the time it returns, and nothing else
    /// would tear that child down. `dispose()` on the never-connected
    /// transport must release it.
    @Test func disposeTerminatesAndReapsANeverConnectedSpawn() async throws {
        let stdio = try Self.makeSleeper(named: "dispose-test")
        let transport = try await stdio.respawn()
        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        #expect(Self.isAlive(pid))

        guard let disposable = transport as? DisposableTransport else {
            Issue.record("expected respawn()'s vended transport to conform to DisposableTransport")
            return
        }
        // Disposed without a `connect()` — the one circumstance `dispose()`
        // exists for.
        await disposable.dispose()

        #expect(Self.isGone(pid))
        #expect(!Self.sharedRegistry.registeredPids.contains(pid))
        Self.confirmNoLeaks()
    }

    /// Whichever `recordSpawn` runs second evicts the first pid. A `dispose()`
    /// on the STALE transport — whose own pid already lost that race — must
    /// be a no-op with respect to the fresher, live process.
    @Test func disposeNeverKillsAFresherConcurrentSpawnThatAlreadyWonTheRace() async throws {
        let stdio = try Self.makeSleeper(named: "dispose-race-test")

        let staleTransport = try await stdio.respawn()
        guard let firstPid = stdio.currentPid else {
            Issue.record("expected first respawn() to record a pid")
            return
        }

        // The second respawn() supersedes the first: it evicts firstPid and
        // becomes the current pid — the documented eviction, reproduced in
        // sequence for a deterministic test.
        _ = try await stdio.respawn()
        guard let secondPid = stdio.currentPid else {
            Issue.record("expected second respawn() to record a pid")
            return
        }
        #expect(secondPid != firstPid)
        #expect(Self.isGone(firstPid))
        #expect(Self.isAlive(secondPid))

        guard let disposable = staleTransport as? DisposableTransport else {
            Issue.record("expected respawn()'s vended transport to conform to DisposableTransport")
            return
        }
        await disposable.dispose()

        #expect(
            Self.isAlive(secondPid),
            "dispose() on a stale transport must never kill a fresher, currently-live process")
        #expect(Self.sharedRegistry.registeredPids == [secondPid])

        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    // MARK: - Owner teardown: releasing every reference reaps via deinit

    /// When nothing holds the `StdioServerProcess` value or the transport it
    /// vended, the spawned process must still be group-killed and reaped,
    /// with no explicit call from anyone: ARC runs the `deinit` of the shared
    /// process state.
    @Test func releasingEveryReferenceReapsTheProcessViaOwnerTeardown() async throws {
        var stdio: StdioServerProcess? = try Self.makeSleeper(named: "owner-teardown-test")

        // The value is unwrapped, spawned and read inside this helper, and the
        // vended transport is discarded there — nothing is bound in this
        // scope. Once it returns, `stdio` (nilled below) is the only remaining
        // strong reference to the shared state.
        guard let pid = try await Self.respawnAndReadPid(stdio) else {
            Issue.record("expected respawn() to record a pid")
            return
        }
        #expect(Self.isAlive(pid))

        stdio = nil

        #expect(Self.isGone(pid))
        #expect(!Self.sharedRegistry.registeredPids.contains(pid))
        Self.confirmNoLeaks()
    }

    /// Spawns `stdio`, discards the vended transport, and returns the pid it
    /// recorded — so no copy of the value and no reference to the transport
    /// escapes into the scope of the caller.
    ///
    /// - Parameter stdio: The process to spawn, or `nil` for none.
    /// - Returns: The recorded pid, or `nil` when there is no process or no
    ///   pid.
    /// - Throws: What `respawn()` throws.
    private static func respawnAndReadPid(_ stdio: StdioServerProcess?) async throws -> pid_t? {
        guard let stdio else { return nil }
        _ = try await stdio.respawn()
        return stdio.currentPid
    }

    // MARK: - env augments (never replaces) the inherited environment

    @Test func envAugmentsRatherThanReplacesTheInheritedEnvironment() async throws {
        let overrideName = "STDIOSERVERPROCESS_TEST_OVERRIDE"
        setenv(overrideName, "parent-value", 1)
        defer { unsetenv(overrideName) }

        let stdio = try StdioServerProcess(
            command: Self.shellCommand,
            args: [Self.shellScriptFlag, "printf '%s|%s\\n' \"$\(overrideName)\" \"$HOME\"; sleep 60"],
            env: [StdioServerProcess.EnvVariable(name: overrideName, value: "child-value")],
            name: "env-augment-test",
            registry: Self.sharedRegistry
        )
        let transport = try await stdio.respawn()
        try await transport.connect()

        guard let line = try await Self.readLines(count: 1, from: transport).first else {
            Issue.record("expected one line of output from the spawned shell")
            await stdio.shutdown()
            return
        }
        let parts = line.split(separator: "|", maxSplits: 1).map(String.init)

        // The explicit override wins over the inherited parent value...
        #expect(parts.first == "child-value")
        // ...but $HOME (absent from `env`) is still visible, which proves an
        // augmented environment and not a replacement.
        #expect(parts.count == 2 && !parts[1].isEmpty)

        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    // MARK: - Reading helpers

    /// Reads `count` lines from the receive stream of `transport`.
    ///
    /// - Parameters:
    ///   - count: How many lines to read.
    ///   - transport: The connected transport to read.
    /// - Returns: The lines, fewer than `count` when the stream ends first.
    /// - Throws: What the receive stream throws.
    private static func readLines(count: Int, from transport: any Transport) async throws -> [String] {
        var lines: [String] = []
        var iterator = await transport.receive().makeAsyncIterator()
        while lines.count < count, let data = try await iterator.next() {
            lines.append(String(decoding: data, as: UTF8.self))
        }
        return lines
    }

    /// Reads `count` pids, one per line, from the receive stream of
    /// `transport`.
    ///
    /// - Parameters:
    ///   - count: How many pids to read.
    ///   - transport: The connected transport to read.
    /// - Returns: The pids each line parsed to.
    /// - Throws: What the receive stream throws.
    private static func readPids(count: Int, from transport: any Transport) async throws -> [pid_t] {
        try await readLines(count: count, from: transport).compactMap {
            pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The number of file descriptors open in this process, through a
    /// `/dev/fd` listing — Darwin exposes exactly one entry per open
    /// descriptor. `-1` when the listing fails.
    ///
    /// - Returns: The count.
    private static func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd"))?.count ?? -1
    }
}
