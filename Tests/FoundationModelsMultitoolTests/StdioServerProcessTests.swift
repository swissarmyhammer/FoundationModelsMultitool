import Foundation
import FoundationModelsExtras
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

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

    /// The absolute path of the long-lived child most tests spawn. The child
    /// reads ``holdFIFO``, and no one writes to that FIFO. Thus the open of
    /// the FIFO blocks, and the child lives until a kill ends it. No time
    /// sets how long it lives.
    private static let holdCommand = "/bin/cat"

    /// The FIFO that each long-lived child of this test reads, and that no
    /// one writes. Its `deinit` removes the FIFO when the test ends.
    private let holdFIFO: ShellCommandGate

    /// The arguments of the long-lived child: the path of ``holdFIFO``.
    private var holdArguments: [String] {
        [holdFIFO.path]
    }

    /// A shell fragment that starts one long-lived child: a `cat` of
    /// ``holdFIFO``, which blocks until a kill ends it.
    private var holdShellCommand: String {
        "\(Self.holdCommand) '\(holdFIFO.path)'"
    }

    /// Makes the FIFO of this test.
    ///
    /// - Throws: What `ShellCommandGate.init()` throws.
    init() throws {
        holdFIFO = try ShellCommandGate()
    }

    /// The absolute path of the shell the tests that need a script spawn.
    private static let shellCommand = "/bin/sh"

    /// The flag that makes the shell read its script from the next argument.
    private static let shellScriptFlag = "-c"

    /// A well-formed (absolute) path that no file system holds, so that
    /// `posix_spawn` itself fails.
    private static let absentCommand = "/nonexistent/binary-that-does-not-exist"

    /// A command that is not an absolute path, which the initializer refuses.
    private static let relativeCommand = "cat"

    /// How many children the group-kill script forks: two backgrounded
    /// `cat`s of ``holdFIFO``.
    private static let forkedChildCount = 2

    /// How many times the leak test makes a spawn fail.
    private static let failedSpawnCount = 50

    /// How many file descriptors one spawn creates before `posix_spawn` runs:
    /// the two ends of the stdin pipe, and the two ends of the stdout pipe.
    private static let pipeFdsPerSpawn = 4

    /// The server name the `mcp-test-server` executable reports at
    /// `initialize` — `serverName` in its `main.swift`.
    private static let testServerReportedName = "mcp-test-server"

    /// The value `fcntl` with `F_GETNOSIGPIPE` gives back for a descriptor
    /// that carries `F_SETNOSIGPIPE`.
    private static let flagIsSet: Int32 = 1

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
    /// The connect-attempt timeout of the server sleeps on a clock that no
    /// test opens. Thus a slow spawn never times the connect or the reconnect
    /// out — see ``MCPTestSupport/makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
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
        let server = MCPTestSupport.makeServer(name: name)
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

    /// A `StdioServerProcess` over ``holdCommand`` with ``holdArguments``,
    /// registered into `sharedRegistry`: a child that lives until a kill
    /// ends it.
    ///
    /// - Parameters:
    ///   - name: The server name of the process.
    ///   - didReap: Called after each teardown reaped and deregistered a
    ///     pid. A no-op by default.
    /// - Returns: The process, not yet spawned.
    /// - Throws: What `StdioServerProcess.init` throws.
    private func makeHeldChild(
        named name: String, didReap: @escaping @Sendable (pid_t) -> Void = { _ in }
    ) throws -> StdioServerProcess {
        try StdioServerProcess(
            command: Self.holdCommand, args: holdArguments, name: name, registry: Self.sharedRegistry,
            didReap: didReap)
    }

    /// Whether `pid` names no live process and no zombie — see
    /// ``ProcessLiveness/isGone(_:)``.
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when the pid is gone.
    private static func isGone(_ pid: pid_t) -> Bool {
        ProcessLiveness.isGone(pid)
    }

    /// Waits until the child `pid` exited and is a zombie, and does not reap
    /// it.
    ///
    /// `waitid` with `WNOWAIT` ends when the child can be reaped, thus when
    /// the exit of the kernel closed each file descriptor of the child. The
    /// child stays a zombie, thus its pid stays its own until the product
    /// reaps it. A kqueue exit event is not enough here: the kernel can send
    /// it before it closed the descriptors.
    ///
    /// `waitid` with no `WNOHANG` blocks its thread until the child exits.
    /// Thus it runs on a thread of its own (``DedicatedThread``), and the
    /// test suspends and holds no thread of the Swift cooperative pool.
    ///
    /// - Parameter pid: A child of this process.
    private static func waitUntilZombie(_ pid: pid_t) async {
        await DedicatedThread.run {
            var info = siginfo_t()
            _ = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
        }
    }

    /// Whether `pid` names a live process (or a zombie) — see
    /// ``ProcessLiveness/isAlive(_:)``.
    ///
    /// - Parameter pid: The pid to probe.
    /// - Returns: `true` when `kill(pid, 0)` succeeds.
    private static func isAlive(_ pid: pid_t) -> Bool {
        ProcessLiveness.isAlive(pid)
    }

    // MARK: - Absolute-path requirement

    @Test func initRejectsANonAbsoluteCommand() {
        #expect(throws: StdioServerProcess.StdioServerProcessError.self) {
            _ = try StdioServerProcess(
                command: Self.relativeCommand, args: holdArguments, name: "relative-path-test",
                registry: Self.sharedRegistry)
        }
    }

    @Test func initAcceptsAnAbsoluteCommand() throws {
        let stdio = try makeHeldChild(named: "absolute-path-test")
        #expect(stdio.command == Self.holdCommand)
        Self.confirmNoLeaks()
    }

    // MARK: - The transport logs through the logger of the library

    @Test("respawn vends a transport whose logger has the label of the library")
    func respawnVendsATransportWithTheLibraryLogger() async throws {
        let stdio = try makeHeldChild(named: "logger-label-test")
        try await ensuring({ await stdio.shutdown() }) {
            let transport = try await stdio.respawn()
            let label = await transport.logger.label

            #expect(label == MultitoolTelemetry.logLabel)
            await stdio.shutdown()
            Self.confirmNoLeaks()
        }
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

        let before = try Self.openFileDescriptorCount()
        for _ in 0..<Self.failedSpawnCount {
            await #expect(throws: StdioServerProcess.StdioServerProcessError.self) {
                _ = try await stdio.respawn()
            }
        }
        let growth = try Self.openFileDescriptorCount() - before

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
        let server = MCPTestSupport.makeServer(name: "spawn-failure-backoff-test", clock: clock)
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
        let stdio = try makeHeldChild(named: "own-group-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    /// The public initializer registers into `ProcessRegistry.global`, thus
    /// the `atexit` sweep behind it reaches a server a host forgot. This test
    /// reads the global registry and sweeps nothing.
    @Test func publicInitRegistersIntoTheGlobalRegistryWhileTheProcessRuns() async throws {
        let stdio = try StdioServerProcess(
            command: Self.holdCommand, args: holdArguments, name: "global-registry-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    // MARK: - respawn() vends a working transport: a real handshake and tool call

    /// `respawn()` vends a working `StdioTransport` wired to a real
    /// subprocess — the `mcp-test-server` executable in echo mode — and a
    /// full MCP `initialize` plus one `tools/call` go through it, not only
    /// raw bytes through a pipe pair.
    @Test func respawnVendsAWorkingTransportThatCompletesAnMCPHandshakeAndToolCall() async throws {
        let stdio = try Self.makeTestServer(mode: .echo, named: "handshake-test")
        try await ensuring({ await stdio.shutdown() }) {
            let (client, initialized) = try await Self.connectClient(
                to: stdio, clientName: "StdioServerProcessTestClient")
            try await MCPTestSupport.withConnection(of: client) {
                #expect(initialized.serverInfo.name == Self.testServerReportedName)

                let (content, isError) = try await client.callTool(
                    name: ScriptedServer.echoToolName,
                    arguments: [ScriptedServer.echoTextArgument: .string(Self.echoedText)])
                #expect(isError != true)
                #expect(content == [.text(text: Self.echoedText, annotations: nil, _meta: nil)])
            }
            await stdio.shutdown()
            Self.confirmNoLeaks()
        }
    }

    // MARK: - Killing the child externally surfaces as a thrown error, never a signal

    /// An unscripted death of the child — `SIGKILL` from outside, never
    /// `shutdown()` — must reach the caller as an ordinary thrown error on
    /// the next call, and never as a `SIGPIPE` that ends the host process.
    ///
    /// The test changes no process-wide state: a change of the `SIGPIPE`
    /// disposition would reach each test that runs at the same time. The
    /// per-descriptor mitigation that keeps the `SIGPIPE` away
    /// (`F_SETNOSIGPIPE`) has its own check in
    /// `theRequestPipeOfTheChildRaisesNoSIGPIPE`, which reads the flag of
    /// the descriptor.
    ///
    /// The reconnect through a fresh spawn that the source went on to prove
    /// stands in `killingTheChildExternallyIsHealedByAReconnectThroughRespawn`.
    @Test func killingTheChildExternallySurfacesAsAThrownErrorAndNotASignal() async throws {
        let stdio = try Self.makeTestServer(mode: .echo, named: "external-kill-test")
        try await ensuring({ await stdio.shutdown() }) {
            let (client, _) = try await Self.connectClient(to: stdio, clientName: "ExternalKillTestClient")
            // The teardown below disconnects the client before the shutdown,
            // and the check after the shutdown reads that order. Thus the
            // explicit disconnect stays in the body.
            try await MCPTestSupport.withConnection(of: client) {
                guard let pid = stdio.currentPid else {
                    Issue.record("expected respawn() to record a pid")
                    return
                }

                // A real, unscripted death. The test waits until the child is a
                // zombie, thus the fds of the child are closed before the call below
                // writes to them. It does NOT reap the child: the product owns the
                // reap. When the test reaped, the teardown below (`disconnect()`,
                // `shutdown()`) sent `killpg` and `waitpid` to a pid that the kernel
                // could already give to an unrelated process.
                kill(pid, SIGKILL)
                await Self.waitUntilZombie(pid)

                // The child is dead, thus the write of the request to its
                // stdin pipe fails, and the transport throws
                // `MCPError.transportError`.
                await MCPTestSupport.expectMCPError(
                    named: "MCPError.transportError",
                    from: {
                        _ = try await client.callTool(
                            name: ScriptedServer.echoToolName,
                            arguments: [ScriptedServer.echoTextArgument: .string(Self.echoedText)])
                    },
                    matching: { error in
                        guard case .transportError = error else { return false }
                        return true
                    })

                await client.disconnect()
                await stdio.shutdown()
                #expect(Self.isGone(pid))
                Self.confirmNoLeaks()
            }
        }
    }

    // MARK: - The request pipe of the child raises no SIGPIPE

    /// The write end of the stdin pipe of the child carries `F_SETNOSIGPIPE`.
    /// Thus a write after the child died fails with `EPIPE`, and no `SIGPIPE`
    /// reaches the host process, whatever the process-wide disposition is.
    ///
    /// The test reads the flag of that one descriptor with
    /// `F_GETNOSIGPIPE`. It changes no process-wide state, thus it is safe
    /// while other tests run.
    @Test func theRequestPipeOfTheChildRaisesNoSIGPIPE() async throws {
        let stdio = try makeHeldChild(named: "no-sigpipe-test")
        try await ensuring({ await stdio.shutdown() }) {
            let transport = try await stdio.respawn()
            let vended = try #require(transport as? StdioServerTransport)

            #expect(fcntl(vended.requestDescriptor.rawValue, F_GETNOSIGPIPE) == Self.flagIsSet)

            await stdio.shutdown()
            Self.confirmNoLeaks()
        }
    }

    // MARK: - An external kill is healed by a reconnect through a fresh spawn

    /// After an unscripted death of the child, `MCPServer.reconnect()` calls
    /// `respawn()` again — the retained transport factory — and heals the
    /// connection with a fresh process: the state is `.ready` again, and the
    /// pid is a new one.
    @Test func killingTheChildExternallyIsHealedByAReconnectThroughRespawn() async throws {
        let stdio = try Self.makeTestServer(mode: .echo, named: "external-kill-reconnect-test")
        try await ensuring({ await stdio.shutdown() }) {
            let server = try await Self.connectServer(through: stdio, named: "external-kill-reconnect-test")
            // The teardown below disconnects the server before the shutdown,
            // and the check after the shutdown reads that order. Thus the
            // explicit disconnect stays in the body.
            try await MCPTestSupport.withConnection(of: server) {
                #expect(await server.state == .ready)
                guard let firstPid = stdio.currentPid else {
                    Issue.record("expected respawn() to record a pid")
                    return
                }

                // The test waits until the child is a zombie and does NOT reap it:
                // the teardown of `respawn()` reaps it. When the test reaped, that
                // teardown sent `killpg` and `waitpid` to a pid that the kernel could
                // already give to an unrelated process.
                kill(firstPid, SIGKILL)
                await Self.waitUntilZombie(firstPid)

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
        }
    }

    // MARK: - name flows into ServerIdentity

    @Test func nameFlowsIntoServerIdentityOnceConnected() async throws {
        let serverName = "stdio-server-process-identity-test"
        let stdio = try Self.makeTestServer(mode: .echo, named: serverName)
        try await ensuring({ await stdio.shutdown() }) {
            let server = try await Self.connectServer(through: stdio, named: serverName)
            try await MCPTestSupport.withConnection(of: server) {
                #expect(await server.identity == ServerIdentity(name: serverName))
            }
            await stdio.shutdown()
            Self.confirmNoLeaks()
        }
    }

    // MARK: - Explicit shutdown group-kills and reaps, asserted by pid

    @Test func shutdownGroupKillsAndReapsAssertedByPid() async throws {
        let stdio = try makeHeldChild(named: "shutdown-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    // MARK: - respawn() tears down whatever it was fronting before spawning fresh

    @Test func respawnTerminatesAndReapsThePreviousProcessBeforeSpawningAFreshOne() async throws {
        let stdio = try makeHeldChild(named: "respawn-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    // MARK: - Concurrent respawn() calls never orphan the losing pid

    /// Two `respawn()` calls on one instance can run at the same time — a
    /// connect attempt that a timeout abandoned is not cancelled, so a retry
    /// can spawn beside it. Whichever `recordSpawn` runs second must not
    /// overwrite the first pid in silence: that would leave a live child
    /// registered but unreachable by every teardown path of the type.
    @Test func concurrentRespawnCallsNeverOrphanTheLosingPid() async throws {
        let stdio = try makeHeldChild(named: "concurrent-respawn-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    // MARK: - Process-group kill also terminates a child the spawned process forked

    /// A server that forks a child of its own must have that child killed too
    /// when this package tears the server down — the reason the spawn goes
    /// into its own process group instead of a kill of the one known pid.
    ///
    /// The script prints the pid of each backgrounded `cat` of ``holdFIFO``,
    /// so the test asserts by pid and not by a count of a process listing.
    ///
    /// A killed grandchild is not a child of this process, thus this process
    /// cannot reap it. The test waits on the exit event of each grandchild
    /// (``ProcessExitWait/waitUntilGone(_:)``), and not on time.
    @Test func groupKillAlsoTerminatesAChildTheSpawnedProcessForkedItself() async throws {
        let stdio = try StdioServerProcess(
            command: Self.shellCommand,
            args: [
                Self.shellScriptFlag,
                "\(holdShellCommand) & echo $!; \(holdShellCommand) & echo $!; wait",
            ],
            name: "group-kill-test",
            registry: Self.sharedRegistry
        )
        let transport = try await stdio.respawn()
        try await ensuring({ await transport.disconnect() }) {
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

            // A killed grandchild is reaped by the system, not by this process.
            // The wait ends on the exit event of the kernel, or on a reading that
            // shows the exit. The end of the wait is the result, thus no state is
            // read again after it. A child that the group kill missed never exits,
            // and that wait is the failure of the test.
            for child in childPids {
                await ProcessExitWait.waitUntilGone(child)
            }
            #expect(Self.isGone(pid))
            Self.confirmNoLeaks()
        }
    }

    // MARK: - Connection teardown (the vended transport's disconnect()) also group-kills and reaps

    @Test func disconnectingTheVendedTransportGroupKillsAndReapsTheProcess() async throws {
        let stdio = try makeHeldChild(named: "connection-teardown-test")
        let transport = try await stdio.respawn()
        try await ensuring({ await transport.disconnect() }) {
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
    }

    // MARK: - DisposableTransport conformance: dispose() reaps a never-connected spawn

    /// A `respawn()` that lost the race against a newer connect attempt has
    /// already spawned a real child by the time it returns, and nothing else
    /// would tear that child down. `dispose()` on the never-connected
    /// transport must release it.
    @Test func disposeTerminatesAndReapsANeverConnectedSpawn() async throws {
        let stdio = try makeHeldChild(named: "dispose-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    /// Whichever `recordSpawn` runs second evicts the first pid. A `dispose()`
    /// on the STALE transport — whose own pid already lost that race — must
    /// be a no-op with respect to the fresher, live process.
    @Test func disposeNeverKillsAFresherConcurrentSpawnThatAlreadyWonTheRace() async throws {
        let stdio = try makeHeldChild(named: "dispose-race-test")
        try await ensuring({ await stdio.shutdown() }) {
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
    }

    // MARK: - Owner teardown: releasing every reference reaps via deinit

    /// When nothing holds the `StdioServerProcess` value or the transport it
    /// vended, the spawned process must still be group-killed and reaped,
    /// with no explicit call from anyone: ARC runs the `deinit` of the shared
    /// process state.
    ///
    /// `deinit` cannot `await`. Thus it gives the kill and the reap to a
    /// thread of its own, and the last release does not wait for the child.
    /// The test waits for the reap event of the process, not for a time. The
    /// event also tells that the reap ran with no current task, thus not on
    /// the task that released the last reference.
    @Test func releasingEveryReferenceReapsTheProcessViaOwnerTeardown() async throws {
        let (reaps, reapsContinuation) = AsyncStream.makeStream(of: OwnerTeardownReap.self)
        var stdio: StdioServerProcess? = try makeHeldChild(named: "owner-teardown-test") { pid in
            reapsContinuation.yield(
                OwnerTeardownReap(pid: pid, ranInATask: withUnsafeCurrentTask { $0 != nil }))
        }

        // The value is unwrapped, spawned and read inside this helper, and the
        // vended transport is discarded there — nothing is bound in this
        // scope. Once it returns, `stdio` (nilled below) is the only remaining
        // strong reference to the shared state.
        let pid = try #require(try await Self.respawnAndReadPid(stdio))
        #expect(Self.isAlive(pid))

        stdio = nil

        var iterator = reaps.makeAsyncIterator()
        let reap = try #require(await iterator.next())
        #expect(reap.pid == pid)
        #expect(!reap.ranInATask)
        #expect(Self.isGone(pid))
        #expect(!Self.sharedRegistry.registeredPids.contains(pid))
        Self.confirmNoLeaks()
    }

    /// One reap event of the owner-teardown test: the pid that the teardown
    /// reaped and deregistered, and whether the event ran with a current
    /// task.
    private struct OwnerTeardownReap: Sendable {
        /// The pid that the teardown reaped and deregistered.
        let pid: pid_t

        /// Whether the event ran with a current task.
        let ranInATask: Bool
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
            args: [
                Self.shellScriptFlag,
                "printf '%s|%s\\n' \"$\(overrideName)\" \"$HOME\"; \(holdShellCommand)",
            ],
            env: [StdioServerProcess.EnvVariable(name: overrideName, value: "child-value")],
            name: "env-augment-test",
            registry: Self.sharedRegistry
        )
        let transport = try await stdio.respawn()
        try await ensuring({ await transport.disconnect() }) {
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
    /// descriptor.
    ///
    /// - Returns: The count.
    /// - Throws: What the listing of `/dev/fd` throws. A listing that fails
    ///   fails the test, and it never counts as a count.
    private static func openFileDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }
}
