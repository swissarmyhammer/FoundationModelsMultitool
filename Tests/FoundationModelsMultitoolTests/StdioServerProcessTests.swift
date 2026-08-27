import Foundation
import FoundationModelsExtras
import MCP
import MCPTestServer
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
/// **Two cases of the source drive the `mcp-test-server` executable over a
/// raw `MCP.Client`** — the handshake-and-tool-call case, and the external
/// kill case reduced to the claim `F_SETNOSIGPIPE` makes. The source drove
/// both over an `MCPServer`.
///
/// **Three cases drive an `MCPServer` over `respawn()` as its transport
/// factory:** the spawn failure that burns no backoff attempt, the name that
/// flows into the identity, and the reconnect after an external kill. The
/// source healed that kill through a faulting call; this package does not
/// port the call path, so the test heals it through `MCPServer.reconnect()`,
/// the host operation that replaced the fault-driven reconnect, and asserts
/// the healed `.ready` state and the fresh pid the source asserted.
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

    /// The server name the `mcp-test-server` executable reports at
    /// `initialize` — `serverName` in its `main.swift`.
    private static let testServerReportedName = "mcp-test-server"

    /// The text the handshake test sends through the echo tool.
    private static let echoedText = "hello"

    /// A per-attempt timeout no attempt of the backoff test reaches.
    private static let generousConnectTimeout = Duration.seconds(10)

    /// The base delay of the backoff test — arbitrary, because the test
    /// asserts that no delay was slept at all.
    private static let backoffBaseDelay = Duration.milliseconds(10)

    /// The delay cap of the backoff test.
    private static let backoffMaxDelay = Duration.seconds(1)

    /// The attempt budget of the backoff test — generous, so a regression
    /// that retried after all shows as a non-empty sleep list.
    private static let backoffMaxAttempts = 5

    /// A `MCPServer` named `name`, connected through the `respawn()` of
    /// `stdio` under `policy`.
    ///
    /// - Parameters:
    ///   - stdio: The process whose `respawn()` is the transport factory.
    ///   - name: The name of the server.
    ///   - policy: The retry policy of the connect.
    /// - Returns: The connected server.
    /// - Throws: What `MCPServer.connect(via:backoffPolicy:)` throws.
    private static func connectServer(
        through stdio: StdioServerProcess, named name: String, policy: BackoffPolicy = .default
    ) async throws -> MCPServer {
        let server = MCPServer(name: name)
        try await server.connect(via: stdio.respawn, backoffPolicy: policy)
        return server
    }

    /// A `StdioServerProcess` over the `mcp-test-server` executable in
    /// `mode`, registered into `sharedRegistry`.
    ///
    /// - Parameters:
    ///   - mode: The tool set the executable registers.
    ///   - name: The server name of the process.
    /// - Returns: The process, not yet spawned.
    /// - Throws: What `TestServerLocator.executableURL()` or
    ///   `StdioServerProcess.init` throws.
    private static func makeTestServer(mode: ServerMode, named name: String) throws -> StdioServerProcess {
        try StdioServerProcess(
            command: TestServerLocator.executableURL().path,
            args: [ServerMode.flagName, mode.rawValue],
            name: name,
            registry: sharedRegistry)
    }

    /// Spawns `stdio` and completes an MCP `initialize` over the vended
    /// transport with a fresh client.
    ///
    /// - Parameters:
    ///   - stdio: The process to spawn.
    ///   - clientName: The client name to log under.
    /// - Returns: The connected client and the result of `initialize`.
    /// - Throws: What `respawn()` or `Client.connect(transport:)` throws.
    private static func connectClient(
        to stdio: StdioServerProcess, clientName: String
    ) async throws -> (client: Client, initialized: Initialize.Result) {
        let transport = try await stdio.respawn()
        let client = MCPTestSupport.makeClient(name: clientName)
        let initialized = try await client.connect(transport: transport)
        return (client, initialized)
    }

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

    /// A `command` that fails to spawn is a permanent configuration error,
    /// not a flaky connection: as the transport factory of an `MCPServer`,
    /// it fails after exactly one attempt, and burns none of the remaining
    /// attempts of `BackoffPolicy` and none of its backoff delay.
    @Test func respawnFailingToSpawnDoesNotBurnBackoffAttemptsWhenUsedAsMCPServerFactory()
        async throws
    {
        let stdio = try StdioServerProcess(
            command: Self.absentCommand, name: "spawn-failure-backoff-test", registry: Self.sharedRegistry)
        let clock = ManualClock()
        let server = MCPServer(name: "spawn-failure-backoff-test", clock: clock)
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.backoffBaseDelay,
            maxDelay: Self.backoffMaxDelay, maxAttempts: Self.backoffMaxAttempts)

        do {
            try await server.connect(via: stdio.respawn, backoffPolicy: policy)
            Issue.record("expected connect(via:backoffPolicy:) to throw")
        } catch let error as MCPServerError {
            guard case .connectConfigurationFailed = error else {
                Issue.record("expected .connectConfigurationFailed, got \(error)")
                return
            }
        }

        // No backoff delay was slept: the spawn failure was classified as
        // permanent on the first attempt.
        #expect(clock.recordedSleeps.isEmpty)
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

    // MARK: - respawn() vends a working transport: a real handshake and tool call

    /// `respawn()` vends a working `StdioTransport` wired to a real
    /// subprocess — the `mcp-test-server` executable in echo mode — and a
    /// full MCP `initialize` plus one `tools/call` go through it, not only
    /// raw bytes through a pipe pair.
    @Test func respawnVendsAWorkingTransportThatCompletesAnMCPHandshakeAndToolCall() async throws {
        let stdio = try Self.makeTestServer(mode: .echo, named: "handshake-test")

        let (client, initialized) = try await Self.connectClient(to: stdio, clientName: "StdioServerProcessTestClient")
        #expect(initialized.serverInfo.name == Self.testServerReportedName)

        let (content, isError) = try await client.callTool(
            name: ScriptedServer.echoToolName,
            arguments: [ScriptedServer.echoTextArgument: .string(Self.echoedText)])
        #expect(isError != true)
        #expect(content == [.text(text: Self.echoedText, annotations: nil, _meta: nil)])

        await client.disconnect()
        await stdio.shutdown()
        Self.confirmNoLeaks()
    }

    // MARK: - Killing the child externally surfaces as a thrown error, never a signal

    /// An unscripted death of the child — `SIGKILL` from outside, never
    /// `shutdown()` — must reach the caller as an ordinary thrown error on
    /// the next call, and never as a `SIGPIPE` that ends the host process.
    ///
    /// The test forces the default `SIGPIPE` disposition (`SIG_DFL`) instead
    /// of ignoring it: `spawn(command:args:env:)` protects the write end of
    /// the stdin pipe of the child with `F_SETNOSIGPIPE`, so a write after
    /// the child died returns `EPIPE` whatever the process-wide disposition
    /// is. That per-fd mitigation is what this proves, deterministically:
    /// with `SIGPIPE` ignored process-wide, the test would pass with the
    /// mitigation removed.
    ///
    /// The reconnect through a fresh spawn that the source went on to prove
    /// stands in `killingTheChildExternallyIsHealedByAReconnectThroughRespawn`.
    @Test func killingTheChildExternallySurfacesAsAThrownErrorAndNotASignal() async throws {
        let previousSigpipeDisposition = signal(SIGPIPE, SIG_DFL)
        defer { signal(SIGPIPE, previousSigpipeDisposition) }

        let stdio = try Self.makeTestServer(mode: .echo, named: "external-kill-test")
        let (client, _) = try await Self.connectClient(to: stdio, clientName: "ExternalKillTestClient")
        guard let pid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }

        // A real, unscripted death — reaped through a blocking `waitpid`,
        // because this process is the parent of the pid — so the fds of the
        // child are closed before the call below writes to them.
        kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        await #expect(throws: (any Error).self) {
            _ = try await client.callTool(
                name: ScriptedServer.echoToolName,
                arguments: [ScriptedServer.echoTextArgument: .string(Self.echoedText)])
        }

        await client.disconnect()
        await stdio.shutdown()
        #expect(Self.isGone(pid))
        Self.confirmNoLeaks()
    }

    // MARK: - An external kill is healed by a reconnect through a fresh spawn

    /// After an unscripted death of the child, `MCPServer.reconnect()` calls
    /// `respawn()` again — the retained transport factory — and heals the
    /// connection with a fresh process: the state is `.ready` again, and the
    /// pid is a new one.
    @Test func killingTheChildExternallyIsHealedByAReconnectThroughRespawn() async throws {
        let stdio = try Self.makeTestServer(mode: .echo, named: "external-kill-reconnect-test")
        let server = try await Self.connectServer(through: stdio, named: "external-kill-reconnect-test")
        #expect(await server.state == .ready)
        guard let firstPid = stdio.currentPid else {
            Issue.record("expected respawn() to record a pid")
            return
        }

        kill(firstPid, SIGKILL)
        var status: Int32 = 0
        waitpid(firstPid, &status, 0)

        try await server.reconnect()

        #expect(await server.state == .ready)
        guard let secondPid = stdio.currentPid else {
            Issue.record("expected the reconnect to have spawned a fresh process")
            return
        }
        #expect(secondPid != firstPid)
        #expect(Self.isAlive(secondPid))

        await server.disconnect()
        await stdio.shutdown()
        #expect(Self.isGone(secondPid))
        Self.confirmNoLeaks()
    }

    // MARK: - name flows into ServerIdentity

    @Test func nameFlowsIntoServerIdentityOnceConnected() async throws {
        let serverName = "stdio-server-process-identity-test"
        let stdio = try Self.makeTestServer(mode: .echo, named: serverName)

        let server = try await Self.connectServer(through: stdio, named: serverName)

        #expect(await server.identity == ServerIdentity(name: serverName))

        await server.disconnect()
        await stdio.shutdown()
        Self.confirmNoLeaks()
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
