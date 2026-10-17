import Logging
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the connection resilience of `MCPServer`: the backoff-retried
/// connect, its exhaustion, the per-attempt timeout against a transport that
/// hangs, the generation guard against a late attempt, the new client of
/// each attempt against a straggler, the teardown that ends each straggler
/// and waits for each pending attempt, and the state machine a host reads.
///
/// A port of `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/ResilienceTests.swift`.
/// Every test drives its own `ManualClock` instead of a real `ContinuousClock`
/// where a backoff schedule is exercised, so a full multi-attempt schedule
/// runs with no real sleep.
///
/// **Five cases of the source are not here.** Each one asserts on the call
/// path — `server.call(toolNamed:)`, `mcpTools()`, a mid-call fault that
/// renders as a `lost` result — which this package does not port; a later
/// task rewrites the call path onto the run plane of Router:
///
/// - `callDuringFaultReturnsErrorResultAndReconnectsToReady`
/// - `modelInitiatedCallDuringFaultReturnsErrorResultAndKeepsWorking`
/// - `callSucceedsAndRendersNormally`
/// - `modelInitiatedFaultReturnsPromptlyRegardlessOfBackoffScheduleLength`
/// - `twoQuickFaultsDoNotStartOverlappingReconnects`
///
/// `explicitConnectDuringInFlightReconnectWins` is here in a new shape: the
/// source triggered the in-flight reconnect through a faulting call, and this
/// port triggers it through `reconnect()`, the host operation that replaced
/// the fault-driven reconnect. The assertions on `mcpTools()` are gone with
/// the call path; the assertions on `state` stand.
@Suite("Resilience")
struct ResilienceTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with, and so the
    /// identity a successful connect establishes.
    private static let serverName = "resilience-test-server"

    /// How many leading connect attempts the flaky transport fails, so the
    /// third succeeds.
    private static let twoFailingAttempts = 2

    /// How many connect attempts the exhaustion test scripts to fail: more
    /// than any policy of this suite allows.
    private static let manyFailingAttempts = 10

    /// The attempt count that succeeds after ``twoFailingAttempts``.
    private static let thirdAttempt = 3

    /// A per-attempt timeout no attempt of the schedule tests reaches.
    private static let generousConnectTimeout = Duration.seconds(10)

    /// The base delay of the schedule test — load-bearing, because
    /// `recordedSleeps` asserts it and its doubling.
    private static let scheduleBaseDelay = Duration.milliseconds(100)

    /// The delay cap of the schedule test, above any delay it reaches.
    private static let scheduleMaxDelay = Duration.seconds(10)

    /// The attempt budget of the schedule test.
    private static let scheduleMaxAttempts = 5

    /// `BackoffPolicy` doubles the delay after each failed attempt — named
    /// here so the doubling `recordedSleeps` asserts cannot drift from a
    /// second literal.
    private static let backoffDoublingFactor = 2

    /// The base delay of the exhaustion test — arbitrary, because it asserts
    /// the attempt count and the state, not the timing.
    private static let exhaustionBaseDelay = Duration.milliseconds(10)

    /// The delay cap of the exhaustion test.
    private static let exhaustionMaxDelay = Duration.seconds(1)

    /// The attempt budget of the exhaustion test.
    private static let exhaustionMaxAttempts = 3

    /// The per-attempt timeout of the hanging-transport test. The test reads
    /// it back from the clock of the attempt, thus the value is arbitrary.
    private static let hangingConnectTimeout = Duration.milliseconds(50)

    /// The per-attempt timeout every gated test holds its gate closed past.
    private static let gatedConnectTimeout = Duration.milliseconds(30)

    /// The one delay a single-attempt policy never sleeps.
    private static let singleAttemptDelay = Duration.milliseconds(1)

    /// The attempt budget of every single-attempt policy.
    private static let singleAttempt = 1

    /// The count of per-attempt timeouts that one connect attempt arms.
    private static let oneArmedTimeout = 1

    /// The per-attempt timeout of the retry in the straggler tests. It
    /// differs from ``gatedConnectTimeout``, thus the test opens the timeout
    /// of the straggler only, and the timeout of the retry never ends. The
    /// value is arbitrary.
    private static let retryConnectTimeout = Duration.milliseconds(40)

    /// The per-attempt timeout of the in-flight reconnect test — shared by
    /// the first connect and, because `reconnect()` reuses the policy of the
    /// connect it followed, the hung second attempt too.
    ///
    /// The timeout sleeps on a `GatedClock` that the test opens only after
    /// the explicit `connect(via:)` reached `.ready`. Thus the generation
    /// bump of the timed-out reconnect always comes after that success, and
    /// the value is arbitrary: the test reads it back from the clock.
    private static let hungReconnectConnectTimeout = Duration.seconds(10)

    /// The attempt count a respawning transport reaches once its reconnect
    /// started: the first connect, plus one reconnect attempt.
    private static let secondAttempt = 2

    /// The name of the tool that only the server of the retry serves. A call
    /// of it succeeds only over the connection of the retry.
    private static let retryOnlyToolName = "retry-only"

    /// The text the tool of the retry answers.
    private static let retryOnlyToolText = "retry"

    // MARK: - Helpers

    /// A `MCPServer` named ``serverName`` over the two given clocks, with
    /// every other setting at the default of the public initializer.
    ///
    /// - Parameters:
    ///   - clock: The clock the retry loop sleeps on. Defaults to a
    ///     `ManualClock`, whose sleeps end at once. A test that reads the
    ///     backoff schedule gives its own `ManualClock`.
    ///   - connectAttemptClock: The clock the per-attempt timeout sleeps on.
    ///     Defaults to a `GatedClock` that no test opens, thus no attempt
    ///     times out, however slow the machine is. A test of the timeout
    ///     gives its own clock (card `^kdtrmhv`: no test checks the speed of
    ///     the machine).
    ///   - logger: The logger the server writes its records to. A test that
    ///     waits for a record gives the logger of
    ///     ``makeStaleConnectDiscardLogger()``.
    /// - Returns: The server, not yet connected.
    private func makeServer(
        clock: any Clock<Duration> = ManualClock(),
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        logger: Logger = MCPServer.defaultLogger
    ) -> MCPServer {
        MCPTestSupport.makeServer(
            name: Self.serverName, clock: clock, connectAttemptClock: connectAttemptClock, logger: logger)
    }

    /// Makes a logger that opens a gate when `MCPServer` records that it
    /// discarded the late result of a stale connect attempt — the last step
    /// that such an attempt makes before it tears its own client down — and
    /// a second gate when `MCPServer` records that an attempt reached
    /// `.ready`.
    ///
    /// The second gate is the failure event of a wait for a discard: a late
    /// success that is not discarded reaches `.ready` and writes that
    /// record in place of the discard record.
    ///
    /// - Returns: The logger to give to the server, the gate that a discard
    ///   record opens, and the gate that a ready record opens.
    private func makeStaleConnectDiscardLogger() -> (logger: Logger, discarded: TestGate, applied: TestGate) {
        let discarded = TestGate()
        let applied = TestGate()
        let logger = Logger(label: "resilience-test.stale-connect-discard") { _ in
            StaleConnectDiscardLogHandler(discarded: discarded, applied: applied)
        }
        return (logger, discarded, applied)
    }

    /// Waits for the first of three events: `discarded` opened, `applied`
    /// opened, or `closed` opened. Then the test fails at once unless the
    /// discard came.
    ///
    /// A stale attempt that discards its late result writes the discard
    /// record, and only then tears its own client down and closes its
    /// transport. Thus when `closed` opened, the discard record came before
    /// it, unless the attempt did not discard. A late success that is not
    /// discarded opens `applied`, and a late failure that is not discarded
    /// closes the transport. Thus each path ends the wait.
    ///
    /// - Parameters:
    ///   - discarded: The gate that the discard record opens.
    ///   - applied: The gate that the record of a ready attempt opens.
    ///   - closed: The gate that the close of the transport of the attempt
    ///     opens.
    /// - Throws: When the attempt did not discard its late result, or when
    ///   the task is cancelled first.
    private func waitForTheDiscard(
        _ discarded: TestGate, orApplied applied: TestGate, orClosed closed: TestGate
    ) async throws {
        try await EventRace.requireOpen(
            discarded, orFirstOf: { try? await applied.wait() }, { try? await closed.wait() },
            orFail: "the stale attempt did not discard its late result")
    }

    /// Starts a fresh `ScriptedServer` on the server end of an in-memory pair
    /// and returns it with the client end.
    ///
    /// - Parameter name: The name the scripted server reports.
    /// - Returns: The scripted server, which the caller keeps alive, and the
    ///   client end of the pair.
    /// - Throws: What `ScriptedServer.start(transport:)` throws.
    private func makeScriptedPair(
        name: String = "ScriptedServer"
    ) async throws -> (scripted: ScriptedServer, transport: any Transport) {
        let scripted = ScriptedServer(name: name)
        let transport = try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory)
        return (scripted, transport)
    }

    /// A policy of one attempt bounded by ``gatedConnectTimeout``, for a test
    /// that holds a gate closed past it.
    private static let oneGatedAttempt = BackoffPolicy(
        connectTimeout: gatedConnectTimeout, baseDelay: singleAttemptDelay,
        maxDelay: singleAttemptDelay, maxAttempts: singleAttempt)

    /// A policy of one attempt bounded by ``retryConnectTimeout``, for the
    /// retry of a straggler test.
    private static let oneRetryAttempt = BackoffPolicy(
        connectTimeout: retryConnectTimeout, baseDelay: singleAttemptDelay,
        maxDelay: singleAttemptDelay, maxAttempts: singleAttempt)

    /// A scripted tool that only the server of the retry serves: it answers
    /// ``retryOnlyToolText`` at once.
    private static var retryOnlyTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: retryOnlyToolName, description: "Only the server of the retry has it.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            CallTool.Result(
                content: [.text(text: retryOnlyToolText, annotations: nil, _meta: nil)], isError: false)
        }
    }

    /// Builds a `RespawningTransport` whose first `connect()` succeeds
    /// against a real `ScriptedServer`, and whose every later `connect()` —
    /// every reconnect attempt — hangs until its task is cancelled, the hang
    /// of `HangingTransport`. Nothing cancels the task of a connect attempt,
    /// thus each such attempt hangs until its timeout abandons it.
    ///
    /// - Parameters:
    ///   - counter: Records every `makePair` call, so a test asserts how many
    ///     attempts were made.
    ///   - hangArrival: The gate that each attempt after the first opens
    ///     before it hangs. A test waits on it to know that a reconnect
    ///     attempt is in flight.
    /// - Returns: The transport.
    private func respawningThatHangsAfterFirstConnect(
        counter: CallCounter, hangArrival: TestGate
    ) -> RespawningTransport {
        RespawningTransport {
            let attempt = counter.increment()
            if attempt == 1 {
                let (client, server) = await InMemoryTransport.createConnectedPair()
                let scripted = ScriptedServer()
                try await scripted.start(transport: server)
                return (client, scripted)
            }
            hangArrival.open()
            // Every reconnect attempt after the first hangs, so the schedule
            // advances only by its per-attempt `connectTimeout`, on the clock
            // of the attempt.
            try await HangingTransport.hangUntilCancelled()
        }
    }

    /// Runs one ``oneGatedAttempt`` connect, and ends its timeout only when
    /// the gated step of the attempt is in flight. Then the attempt is always
    /// orphaned, and the connect always throws, however slow the machine is
    /// (card `^kdtrmhv`). A timeout that ended before the gated step began
    /// would skip that step, and leave no orphan to test. The wait for the
    /// gated step also ends when the connect ends, and the test then fails
    /// at once.
    ///
    /// - Parameters:
    ///   - server: The server to connect. Its attempt clock is `attemptClock`.
    ///   - attemptClock: The clock the timeout of the attempt sleeps on.
    ///   - inFlight: The gate that the gated step of the attempt opens when
    ///     it is called.
    ///   - connect: Starts the connect on `server`.
    private func connectUntilOrphaned(
        _ server: MCPServer, attemptClock: GatedClock, inFlight: TestGate,
        connect: @escaping @Sendable () async throws -> Void
    ) async throws {
        let connecting = try await EventRace.watch(
            connect, untilOpen: inFlight, orFail: "the connect ended before its gated step was in flight"
        ).task
        attemptClock.open()
        await #expect(throws: MCPServerError.self) {
            try await connecting.value
        }
        await expectStillConnecting(server)
    }

    /// Runs one ``oneGatedAttempt`` connect over `gated`, and ends only the
    /// timeout of ``gatedConnectTimeout`` when the connect of `gated` is in
    /// flight. Then the attempt is a straggler that holds its connect at the
    /// gate of `gated`, and each later timeout of another duration still
    /// waits on `attemptClock`. The waits for the timeout and for the connect
    /// of `gated` also end when the first attempt ends, and the test then
    /// fails at once.
    ///
    /// - Parameters:
    ///   - gated: The transport whose connect the straggler holds.
    ///   - server: The server to connect. Its attempt clock is `attemptClock`.
    ///   - attemptClock: The clock the timeout of each attempt sleeps on.
    private func orphanStraggler(
        over gated: GatedConnectTransport, on server: MCPServer, attemptClock: GatedClock
    ) async throws {
        let firstAttempt = try await EventRace.watch(
            { try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt) },
            awaiting: {
                try? await attemptClock.waitForRecordedSleeps(atLeast: Self.oneArmedTimeout)
                try? await gated.connectArrival.wait()
            },
            requiring: { attemptClock.recordedSleeps.count >= Self.oneArmedTimeout && gated.connectArrival.isOpen },
            orFail: "the first attempt ended before it armed its timeout and held its connect"
        ).task
        attemptClock.open(sleepsOf: Self.gatedConnectTimeout)
        await #expect(throws: MCPServerError.self) {
            try await firstAttempt.value
        }
    }

    /// Records a failure unless `server` is `.connecting` — the state an
    /// orphaned attempt, still blocked on a gate, leaves behind once the
    /// retry loop gave up.
    ///
    /// - Parameter server: The server to read.
    private func expectStillConnecting(_ server: MCPServer) async {
        let state = await server.state
        #expect(state == .connecting, "expected .connecting, the orphaned attempt is still blocked")
    }

    /// Starts a disconnect of `server`, waits until the disconnect called
    /// the `disconnect()` of `gatedDisconnect`, and fails the test at once
    /// when the disconnect ended first — see
    /// ``EventRace/watch(_:untilOpen:orFail:sourceLocation:)``.
    ///
    /// The gate of `gatedDisconnect` then holds the disconnect in flight.
    ///
    /// - Parameters:
    ///   - server: The server to disconnect.
    ///   - gatedDisconnect: The transport that holds its `disconnect()` at a
    ///     gate.
    /// - Returns: The task of the disconnect.
    /// - Throws: When the disconnect ended before it closed the old
    ///   transport, or when the task is cancelled first.
    private static func startDisconnectAwaitingClose(
        of server: MCPServer, gate gatedDisconnect: GatedDisconnectTransport
    ) async throws -> Task<Void, any Error> {
        try await EventRace.watch(
            { await server.disconnect() }, untilOpen: gatedDisconnect.disconnectArrival,
            orFail: "the disconnect ended before it closed the old transport"
        ).task
    }

    /// Records a failure unless `waitUntilReady()` throws `notReady` carrying
    /// `expected`.
    ///
    /// - Parameters:
    ///   - server: The server to wait on.
    ///   - expected: The state the error must carry.
    private func expectWaitUntilReadyThrowsNotReady(
        _ server: MCPServer, carrying expected: MCPServerState
    ) async {
        do {
            try await server.waitUntilReady()
            Issue.record("expected waitUntilReady() to throw")
        } catch let MCPServerError.notReady(state) {
            #expect(state == expected)
        } catch {
            Issue.record("expected MCPServerError.notReady, got \(error)")
        }
    }

    /// Records a failure unless `body` throws `backoffExhausted` that names
    /// ``serverName`` and carries `attempts`.
    ///
    /// - Parameters:
    ///   - attempts: The attempt count the error must carry.
    ///   - body: The work that must throw the error.
    private func expectBackoffExhausted(
        after attempts: Int, from body: () async throws -> Void
    ) async {
        do {
            try await body()
            Issue.record("expected MCPServerError.backoffExhausted, and nothing was thrown")
        } catch let MCPServerError.backoffExhausted(serverName, attemptCount, _) {
            #expect(serverName == Self.serverName)
            #expect(attemptCount == attempts)
        } catch {
            Issue.record("expected MCPServerError.backoffExhausted, got \(error)")
        }
    }

    // MARK: - Backoff schedule

    @Test func connectSucceedsOnThirdAttemptWithExpectedSchedule() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.twoFailingAttempts)
        let clock = ManualClock()
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.scheduleBaseDelay,
            maxDelay: Self.scheduleMaxDelay, maxAttempts: Self.scheduleMaxAttempts)

        let server = makeServer(clock: clock)
        try await MCPTestSupport.withConnection(of: server) {
            try await server.connect(via: flaky, backoffPolicy: policy)

            #expect(await server.state == .ready)
            #expect(await flaky.connectAttempts == Self.thirdAttempt)
            #expect(
                clock.recordedSleeps == [
                    Self.scheduleBaseDelay, Self.scheduleBaseDelay * Self.backoffDoublingFactor,
                ])
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Exhaustion

    @Test func connectThrowsTypedErrorNamingServerIdentityWhenExhausted() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.manyFailingAttempts)
        let clock = ManualClock()
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.exhaustionBaseDelay,
            maxDelay: Self.exhaustionMaxDelay, maxAttempts: Self.exhaustionMaxAttempts)

        let server = makeServer(clock: clock)

        await expectBackoffExhausted(after: Self.exhaustionMaxAttempts) {
            try await server.connect(via: flaky, backoffPolicy: policy)
        }

        guard case .faulted = await server.state else {
            Issue.record("expected .faulted state after exhausted backoff")
            return
        }
    }

    // MARK: - Per-attempt timeout ends an attempt whose transport hangs

    /// The `connect()` of the hanging transport never returns, and the
    /// timeout of the attempt sleeps on a `GatedClock`. Thus the connect can
    /// end only when the test opens the clock, and the clock records the
    /// timeout that the attempt armed. A retry loop that blocks on the
    /// abandoned attempt makes the test hang. The test reads no real time
    /// (card `^tm4x2hp`: no test checks the speed of the machine).
    @Test
    func connectAttemptTimeoutEndsTheAttemptEvenWhenTransportHangs() async throws {
        let hanging = HangingTransport()
        let policy = BackoffPolicy(
            connectTimeout: Self.hangingConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        // The wait for the timeout also ends when the connect ends.
        let connecting = try await EventRace.watch(
            { try await server.connect(via: hanging, backoffPolicy: policy) },
            awaiting: { try? await attemptClock.waitForRecordedSleeps(atLeast: Self.oneArmedTimeout) },
            requiring: { attemptClock.recordedSleeps.count >= Self.oneArmedTimeout },
            orFail: "the connect ended before it armed its timeout"
        ).task
        attemptClock.open()

        await #expect(throws: MCPServerError.self) {
            try await connecting.value
        }
        #expect(attemptClock.recordedSleeps == [Self.hangingConnectTimeout])
    }

    /// The gate holds the attempt in its connect, and the test ends the
    /// timeout of the attempt only then. Thus the timeout always wins, however
    /// slow the machine is.
    ///
    /// The test waits for the record of the discard, the last step of the
    /// orphaned attempt, and then reads the state. It waits for no fixed
    /// time.
    @Test
    func lateResolvingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let gated = GatedConnectTransport(wrapping: clientTransport)
        let attemptClock = GatedClock()
        let (logger, discarded, applied) = makeStaleConnectDiscardLogger()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock, logger: logger)

        // The `ensuring` opens the gate on each path. Thus no attempt stays
        // parked at the gate when the body throws.
        try await ensuring({ await gated.release() }) {
            // The gate stays closed past connectTimeout, so this attempt times
            // out and backoff is exhausted while the orphaned attempt is still
            // blocked in the background.
            try await connectUntilOrphaned(server, attemptClock: attemptClock, inFlight: gated.connectArrival) {
                try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
            }

            // Now let the orphaned attempt succeed, and wait until the server
            // discarded its late result.
            await gated.release()
            try await waitForTheDiscard(discarded, orApplied: applied, orClosed: gated.closeArrival)

            // The late success was discarded: no identity, and not ready.
            #expect(await server.identity == nil)
            #expect(await server.state != .ready)
        }
        withExtendedLifetime(scripted) {}
    }

    /// The sibling of ``lateResolvingAttemptAfterExhaustionIsDiscarded()``
    /// for the other stale-generation guard — the one in the `catch` block,
    /// which discards a late FAILURE. The wrapped `FlakyConnectTransport`
    /// makes the now-late attempt fail its handshake instead of succeeding,
    /// so this proves the late failure never reaches `.faulted` either.
    @Test
    func lateFailingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let flaky = FlakyConnectTransport(wrapping: clientTransport, failingConnectAttempts: 1)
        let gated = GatedConnectTransport(wrapping: flaky)
        let attemptClock = GatedClock()
        let (logger, discarded, applied) = makeStaleConnectDiscardLogger()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock, logger: logger)

        // The `ensuring` opens the gate on each path.
        try await ensuring({ await gated.release() }) {
            try await connectUntilOrphaned(server, attemptClock: attemptClock, inFlight: gated.connectArrival) {
                try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
            }

            // Now let the orphaned attempt fail its handshake, and wait until the
            // server discarded the late failure.
            await gated.release()
            try await waitForTheDiscard(discarded, orApplied: applied, orClosed: gated.closeArrival)

            // The late failure was discarded too: the state stays where the
            // reported exhaustion left it, and is not overwritten with `.faulted`.
            #expect(await server.state == .connecting)
        }
        withExtendedLifetime(scripted) {}
    }

    /// Closes the window between `factory()` returning and the new client of
    /// the attempt being connected over its result: an attempt a newer one
    /// already superseded must never hand its factory-built transport to a
    /// client, and must release the transport instead. Only a gated FACTORY
    /// reaches this window — by the time a gated transport opens, the
    /// factory already returned.
    @Test
    func lateResolvingFactoryAfterExhaustionDisposesAbandonedTransport() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let spy = DisposableSpyTransport(wrapping: clientTransport)
        let gatedFactory = GatedTransportFactory { spy }
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        // The `ensuring` opens the factory gate on each path.
        try await ensuring({ await gatedFactory.release() }) {
            try await connectUntilOrphaned(
                server, attemptClock: attemptClock, inFlight: gatedFactory.makeArrival
            ) {
                try await server.connect(
                    via: { try await gatedFactory.make() }, backoffPolicy: Self.oneGatedAttempt)
            }

            // The dispose is the event the abandoned attempt ends with: wait for
            // it, and never for a fixed time. The wait also ends when the
            // attempt connects the transport in place of the dispose.
            await gatedFactory.release()
            try await EventRace.requireOpen(
                spy.disposeArrival, orFirstOf: { try? await spy.connectArrival.wait() },
                orFail: "the abandoned attempt did not release its transport")

            // Never connected, and disposed — the resource leak is closed.
            #expect(await spy.connectWasCalled == false)
            #expect(await server.identity == nil)
            #expect(await server.state != .ready)
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A straggler cannot change the connection of a retry

    /// An attempt that passed its `connectTimeout` keeps running inside the
    /// connect of its own client: a straggler. Each attempt has its own
    /// client, thus the retry connects at once over its own transport, and
    /// does not wait for the straggler. When the straggler ends later, the
    /// generation guard discards its result, and the straggler closes its
    /// own transport. The current connection stays the connection of the
    /// retry.
    ///
    /// The order is fixed, and no load can change it (card `^kdtrmhv`):
    ///
    /// 1. The first attempt holds its connect at the gate of its transport,
    ///    and the test ends only its timeout.
    /// 2. The retry connects over its own transport and reaches `.ready`.
    ///    Its timeout has another duration, and never ends.
    /// 3. The test lets the straggler end, and waits for the record of the
    ///    discard and for the close of the transport of the straggler.
    /// 4. A call of the tool that only the server of the retry serves
    ///    succeeds: the current connection did not change.
    @Test
    func aStragglerThatEndsAfterTheRetryLeavesTheConnectionOfTheRetry() async throws {
        let (straggler, stragglerTransport) = try await makeScriptedPair(name: "straggler-server")
        let gated = GatedConnectTransport(wrapping: stragglerTransport)
        let fresh = ScriptedServer(name: "fresh-server")
        await fresh.addTool(Self.retryOnlyTool)
        let freshTransport = try await MCPTestSupport.clientTransport(serving: fresh, over: .inMemory)
        let attemptClock = GatedClock()
        // The retry reaches `.ready` and writes the record that opens the
        // second gate. Thus the wait for the discard of the straggler does
        // not use that gate.
        let (logger, discarded, _) = makeStaleConnectDiscardLogger()
        let server = makeServer(connectAttemptClock: attemptClock, logger: logger)

        try await MCPTestSupport.withConnection(of: server) {
            // The inner `ensuring` opens the gate also when the body throws.
            try await ensuring({ await gated.release() }) {
                // 1. The straggler holds its connect.
                try await orphanStraggler(over: gated, on: server, attemptClock: attemptClock)

                // 2. The retry becomes ready while the straggler still holds its connect.
                try await server.connect(via: freshTransport, backoffPolicy: Self.oneRetryAttempt)
                #expect(await server.state == .ready)
                #expect(await gated.isOpen == false)

                // 3. The straggler ends: its result is discarded, and its transport closes.
                // The wait for the discard also ends when the transport closes.
                await gated.release()
                try await EventRace.requireOpen(
                    discarded, orFirstOf: { try? await gated.closeArrival.wait() },
                    orFail: "the straggler did not discard its late result")
                try await gated.closeArrival.wait()

                // 4. The connection of the retry still answers.
                let result = try await server.call(name: Self.retryOnlyToolName)
                #expect(result.isError != true)
                #expect(result.content == [.text(text: Self.retryOnlyToolText, annotations: nil, _meta: nil)])
                #expect(await server.state == .ready)
                #expect(await gated.isOpen == false)
            }
        }
        withExtendedLifetime((straggler, fresh)) {}
    }

    // MARK: - The teardown ends each straggler and each pending attempt

    /// Starts `server.disconnect()`, and waits for the first of two events:
    /// the teardown returned, or the teardown waits for the close of an open
    /// attempt — the test hook `waitUntilTransportCloseIsAwaited()`. Each of
    /// the two events can occur, thus the wait always ends, and the caller
    /// reads which event came first without a clock.
    ///
    /// - Parameter server: The server to tear down.
    /// - Returns: The task of the teardown, and whether the teardown
    ///   returned before the first event ended the wait.
    private func startTeardown(
        of server: MCPServer
    ) async throws -> (teardown: Task<Void, any Error>, returnedFirst: Bool) {
        let teardown = EventRace.watch { await server.disconnect() }
        // The race cancels the wait of the hook when the teardown never waits.
        try await EventRace.firstOf(
            { await teardown.waitForEnd() }, or: { await server.waitUntilTransportCloseIsAwaited() })
        return (teardown.task, teardown.ended.isOpen)
    }

    /// A teardown must not wait forever for work that it can stop. A
    /// straggler whose transport `connect()` never returns is ended by the
    /// teardown: the teardown calls the `disconnect()` of that transport
    /// itself, and returns once the transport closed.
    ///
    /// The order is fixed, and no load can change it (card `^kdtrmhv`):
    ///
    /// 1. The first attempt holds its connect at the gate of its transport,
    ///    and the test ends only its timeout. The test never opens that gate.
    /// 2. The teardown starts. The test waits for the first of two events:
    ///    the teardown returned, or the teardown waits for a close.
    /// 3. The teardown returned first. The transport closed, and its
    ///    `connect()` ended because of that close.
    ///
    /// A teardown that waits for the straggler makes step 3 fail as a check:
    /// the test then opens the gate itself, so that the straggler ends and
    /// the test ends. A body that throws also opens the gate, after the
    /// body: thus no attempt stays parked at the gate. On the path that
    /// passes, the gate opens only after each check.
    @Test
    func disconnectEndsAStragglerWhoseConnectNeverReturns() async throws {
        let (straggler, stragglerTransport) = try await makeScriptedPair(name: "straggler-server")
        let gated = GatedConnectTransport(wrapping: stragglerTransport)
        let attemptClock = GatedClock()
        let server = makeServer(connectAttemptClock: attemptClock)

        try await ensuring({ await gated.release() }) {
            // 1. The straggler holds its connect, and the gate never opens.
            try await orphanStraggler(over: gated, on: server, attemptClock: attemptClock)

            // 2. The teardown starts.
            let (teardown, returnedFirst) = try await startTeardown(of: server)

            // 3. The teardown ended the straggler.
            #expect(returnedFirst, "the teardown waits for a straggler whose connect never returns")
            if !returnedFirst {
                await gated.release()
            }
            try await teardown.value
            // The teardown returns once the transport closed. Thus the close
            // came, or the test fails at once. The close releases the gate,
            // and the connect of the double then ends.
            try #require(gated.closeArrival.isOpen, "the teardown returned before the transport closed")
            try await gated.connectEnd.wait()
            #expect(await gated.connectEndedByClose)
            #expect(await gated.isOpen == false)
            #expect(await server.state == .disconnected)
        }
        withExtendedLifetime(straggler) {}
    }

    /// The factory of an attempt can return a transport after the teardown
    /// started. The teardown must wait until that factory returned and its
    /// transport was released, and the attempt must never connect that
    /// transport. Thus no transport and no process appears after
    /// `disconnect()` returned.
    ///
    /// The order is fixed, and no load can change it (card `^kdtrmhv`):
    ///
    /// 1. The attempt holds its factory at a gate.
    /// 2. The teardown starts. The test waits for the first of two events:
    ///    the teardown returned, or the teardown waits for the attempt. The
    ///    teardown must not have returned.
    /// 3. The test opens the factory gate. The teardown returns, and by then
    ///    the transport of the factory was released and never connected.
    @Test
    func disconnectWaitsForTheFactoryOfAPendingAttempt() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let spy = DisposableSpyTransport(wrapping: clientTransport)
        let gatedFactory = GatedTransportFactory { spy }
        let attemptClock = GatedClock()
        let server = makeServer(connectAttemptClock: attemptClock)

        // The `ensuring` opens the factory gate on each path.
        try await ensuring({ await gatedFactory.release() }) {
            // 1. The attempt holds its factory. The wait also ends when the
            // connect ends.
            let connecting = try await EventRace.watch(
                {
                    try await server.connect(
                        via: { try await gatedFactory.make() }, backoffPolicy: Self.oneGatedAttempt)
                },
                untilOpen: gatedFactory.makeArrival, orFail: "the connect ended before the factory was called"
            ).task

            // 2. The teardown starts, and waits for the attempt.
            let (teardown, returnedFirst) = try await startTeardown(of: server)
            #expect(!returnedFirst, "the teardown returned while the factory of an attempt was held")

            // 3. The factory returns; the teardown returns after the release.
            await gatedFactory.release()
            try await teardown.value
            #expect(await spy.disposeWasCalled, "the transport of the factory was not released before the teardown returned")
            #expect(await spy.connectWasCalled == false)
            #expect(await server.state == .disconnected)

            // The teardown made the attempt stale. A stale attempt releases
            // its transport and returns with no error, thus an error of the
            // connect fails the test.
            try await connecting.value
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A disconnect whose transport hangs does not block a fresh connect

    /// A real `MCPServer.disconnect()` whose old transport holds its
    /// `disconnect()` at a gate — the stand-in for a disconnect that does not
    /// return. A fresh connect starts while that disconnect is in flight. It
    /// must not wait for it: the fresh connect makes its own client, and the
    /// old client was taken out before the disconnect waited.
    ///
    /// The fresh transport holds its own connect at a gate, thus the fresh
    /// connect cannot reach `.ready` before the first disconnect wrote
    /// `.disconnected`.
    @Test func freshConnectIsNotBlockedByADisconnectWhoseTransportHangs() async throws {
        let (initial, clientTransport1) = try await makeScriptedPair(name: "initial-server")
        let gatedDisconnect = GatedDisconnectTransport(wrapping: clientTransport1)

        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let gatedConnect = GatedConnectTransport(wrapping: clientTransport2)
        let server = makeServer()
        // The inner `ensuring` opens the disconnect gate and the connect gate
        // also when the body throws. Thus no disconnect and no connect stays
        // parked at a gate after the test.
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({
                await gatedDisconnect.release()
                await gatedConnect.release()
            }) {
                try await server.connect(via: gatedDisconnect, backoffPolicy: .default)
                #expect(await server.state == .ready)

                // The first disconnect tears the old client down, and the transport
                // of that client then holds it in flight. Each wait below also
                // ends when its work ends.
                let firstDisconnect = try await Self.startDisconnectAwaitingClose(of: server, gate: gatedDisconnect)

                let spy = DisposableSpyTransport(wrapping: gatedConnect)
                // The fresh attempt connects its own transport while the first
                // disconnect is still in flight.
                let attempt2 = try await EventRace.watch(
                    { try await server.connect(via: spy, backoffPolicy: .default) },
                    untilOpen: spy.connectArrival, orFail: "the fresh connect ended before it connected its transport"
                ).task

                // The first disconnect ends, and writes `.disconnected`. Then the
                // fresh attempt ends, and writes `.ready`.
                await gatedDisconnect.release()
                try await firstDisconnect.value
                #expect(await server.state == .disconnected)
                await gatedConnect.release()
                try await attempt2.value
                #expect(await server.state == .ready)
            }
        }

        withExtendedLifetime((initial, fresh)) {}
    }

    // MARK: - A late disconnect of an old client never closes the current connection

    /// The teardown of an old client can end long after a new connect made
    /// the current connection. That late teardown must close the transport
    /// of the old client only, and never the connection of the new client.
    ///
    /// The order is fixed, and no load can change it (card `^kdtrmhv`):
    ///
    /// 1. A disconnect tears the first client down, and the gated transport
    ///    of that client holds its `disconnect()` in flight.
    /// 2. A connect makes a new client over a new transport, and returns.
    /// 3. The test lets the old transport close, and waits until the
    ///    disconnect returned.
    /// 4. The new connection must still answer a request.
    @Test func aLateDisconnectOfAnOldClientNeverClosesTheCurrentConnection() async throws {
        let (initial, clientTransport1) = try await makeScriptedPair(name: "initial-server")
        let gatedDisconnect = GatedDisconnectTransport(wrapping: clientTransport1)
        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let server = makeServer()
        // The inner `ensuring` opens the disconnect gate also when the body
        // throws. Thus no disconnect stays parked at the gate after the test.
        try await MCPTestSupport.withConnection(of: server) {
            try await ensuring({ await gatedDisconnect.release() }) {
                try await server.connect(via: gatedDisconnect)

                // 1. The disconnect tears the first client down, and stays in flight.
                // The wait also ends when the disconnect ends.
                let firstDisconnect = try await Self.startDisconnectAwaitingClose(of: server, gate: gatedDisconnect)

                // 2. The connect makes the new connection, and returns.
                try await server.connect(via: clientTransport2)
                let newClient = try #require(await server.client)

                // 3. The old transport closes, and the disconnect ends.
                await gatedDisconnect.release()
                try await firstDisconnect.value

                // 4. The new connection still answers.
                _ = try await newClient.listTools()
                #expect(await server.client === newClient)
            }
        }

        withExtendedLifetime((initial, fresh)) {}
    }

    // MARK: - An explicit connect wins against an in-flight reconnect

    /// The timeout of each connect attempt sleeps on a `GatedClock`. No
    /// timeout ends before the test opens it, thus the order of the events is
    /// the order the test states, and no load can change it (card
    /// `^kdtrmhv`: no test checks the speed of the machine):
    ///
    /// 1. The reconnect starts its second attempt, which hangs, and the
    ///    attempt arms its timeout.
    /// 2. The explicit `connect(via:)` makes its own client, and reaches
    ///    `.ready` at once: it does not wait for the hung attempt.
    /// 3. The test ends the timeout of the hung attempt. The reconnect gives
    ///    up and bumps the generation, and its stale result must not move
    ///    the state.
    @Test
    func explicitConnectDuringInFlightReconnectWins() async throws {
        let counter = CallCounter()
        let hangArrival = TestGate()
        let respawning = respawningThatHangsAfterFirstConnect(counter: counter, hangArrival: hangArrival)
        let policy = BackoffPolicy(
            connectTimeout: Self.hungReconnectConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let attemptClock = GatedClock()
        let (fresh, freshTransport) = try await makeScriptedPair(name: "fresh-server")
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)
        try await MCPTestSupport.withConnection(of: server) {
            try await server.connect(via: respawning, backoffPolicy: policy)
            #expect(await server.state == .ready)

            await respawning.disconnect()
            // The hung second attempt is in flight, and armed its timeout. The
            // wait also ends when the reconnect ends.
            let reconnect = try await EventRace.watch(
                { try await server.reconnect() },
                awaiting: {
                    try? await hangArrival.wait()
                    try? await attemptClock.waitForRecordedSleeps(atLeast: Self.secondAttempt)
                },
                requiring: { hangArrival.isOpen && attemptClock.recordedSleeps.count >= Self.secondAttempt },
                orFail: "the reconnect ended before its second attempt hung and armed its timeout"
            ).task
            #expect(counter.count == Self.secondAttempt)
            #expect(attemptClock.recordedSleeps.count == Self.secondAttempt)

            try await server.connect(via: freshTransport)
            #expect(await server.state == .ready)

            attemptClock.open()
            // The reconnect has one attempt, and the timeout ended it. Thus
            // the reconnect throws `backoffExhausted`. Each other error, and no
            // error, fails the test.
            await expectBackoffExhausted(after: Self.singleAttempt) {
                try await reconnect.value
            }
            #expect(await server.state == .ready)
            #expect(attemptClock.recordedSleeps == [Self.hungReconnectConnectTimeout, Self.hungReconnectConnectTimeout])
        }
        withExtendedLifetime(fresh) {}
    }

    // MARK: - The capability the client declares

    /// The `initialize` request carries the elicitation capability with both
    /// `form` and `url` — read off the server end, which is what proves the
    /// wire carried it, and not only that the client held it.
    @Test func initializeCarriesElicitationCapabilityWithFormAndURL() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            #expect(await server.state == .ready)

            let received = try #require(await scripted.receivedClientCapabilities)
            let elicitation = try #require(received.elicitation)
            #expect(elicitation.form != nil)
            #expect(elicitation.url != nil)

            // The client the actor built declares the same, as `@testable` sees.
            let client = try #require(await server.client)
            let declared = await client.capabilities
            #expect(declared.elicitation == elicitation)
        }
    }

    /// A headless server declares no elicitation capability at `initialize`:
    /// no person can answer a question, thus the server must not get one.
    /// The test reads the capability off the server end, which is what
    /// proves the wire did not carry it, and off the client the actor built.
    @Test func headlessInitializeCarriesNoElicitationCapability() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName, userPresence: .headless)
        try await MCPTestSupport.withConnection(of: server) {
            #expect(await server.state == .ready)

            let received = try #require(await scripted.receivedClientCapabilities)
            #expect(received.elicitation == nil)

            let client = try #require(await server.client)
            let declared = await client.capabilities
            #expect(declared.elicitation == nil)
        }
    }

    // MARK: - The state machine a host reads

    @Test func disconnectMovesStateToDisconnectedAndKeepsIdentity() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)

        try await MCPTestSupport.withConnection(of: server) {
            // The disconnect under test. The second disconnect of the
            // helper does nothing.
            await server.disconnect()

            #expect(await server.state == .disconnected)
            #expect(await server.identity == ServerIdentity(name: Self.serverName))
            await expectWaitUntilReadyThrowsNotReady(server, carrying: .disconnected)
        }
    }

    @Test func waitUntilReadyAfterAFaultThrowsNotReady() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.manyFailingAttempts)
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.exhaustionBaseDelay,
            maxDelay: Self.exhaustionMaxDelay, maxAttempts: Self.exhaustionMaxAttempts)
        let server = makeServer(clock: ManualClock())

        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: flaky, backoffPolicy: policy)
        }

        let faulted = await server.state
        guard case .faulted = faulted else {
            Issue.record("expected .faulted state after exhausted backoff")
            return
        }
        await expectWaitUntilReadyThrowsNotReady(server, carrying: faulted)
    }

    @Test func waitUntilReadyReturnsOnceAGatedConnectCompletes() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let gated = GatedConnectTransport(wrapping: clientTransport)
        let server = makeServer()

        try await MCPTestSupport.withConnection(of: server) {
            let connecting = Task { try await server.connect(via: gated) }
            let waiting = Task { try await server.waitUntilReady() }

            await gated.release()
            try await connecting.value
            try await waiting.value

            #expect(await server.state == .ready)
        }
        withExtendedLifetime(scripted) {}
    }

    /// A cancel ends a wait of `waitUntilReady()` with `CancellationError`.
    ///
    /// The order is fixed. The test cancels the wait before it releases the
    /// gated connect. Thus each event that the wait sees comes after the
    /// cancel, and the wait must end with `CancellationError`, also when the
    /// server reached `.ready` before the wait read the state. A wait that
    /// does not end on the cancel ends when the connect makes the server
    /// ready, thus the test fails and does not hang.
    @Test func aCancelEndsWaitUntilReadyWithCancellationError() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let gated = GatedConnectTransport(wrapping: clientTransport)
        let server = makeServer()

        try await MCPTestSupport.withConnection(of: server) {
            let connecting = Task { try await server.connect(via: gated) }
            let waiting = Task { try await server.waitUntilReady() }
            waiting.cancel()

            await gated.release()
            try await connecting.value
            let outcome = await waiting.result

            #expect(throws: CancellationError.self) { try outcome.get() }
        }
        withExtendedLifetime(scripted) {}
    }
}

/// A `LogHandler` that opens a gate when `MCPServer` records that it
/// discarded the late result of a stale connect attempt: a late success or a
/// late failure. That record is the last step of an orphaned attempt before
/// it tears its own client down. Thus a test waits on the gate in place of a
/// fixed sleep, and then reads the state that the attempt left.
///
/// It opens a second gate when `MCPServer` records that an attempt reached
/// `.ready`: the record that a late success writes when it is not
/// discarded. It ignores every other record.
private struct StaleConnectDiscardLogHandler: LogHandler {
    /// The messages of the records that open the gate.
    private static let discardMessages: Set<String> = [
        MultitoolTelemetry.LogMessage.mcpStaleSuccessDiscarded.rawValue,
        MultitoolTelemetry.LogMessage.mcpStaleFailureDiscarded.rawValue,
    ]

    /// The message of the record of an attempt that reached `.ready`.
    private static let appliedMessage = MultitoolTelemetry.LogMessage.mcpServerInitialized.rawValue

    /// The gate that a discard record opens.
    let discarded: TestGate

    /// The gate that the record of an attempt that reached `.ready` opens.
    let applied: TestGate

    /// The metadata of the handler. The handler does not read it.
    var metadata: Logger.Metadata = [:]

    /// The lowest level that the handler gets: each level, so that no
    /// discard record is filtered out.
    var logLevel: Logger.Level = .trace

    /// Reads or writes one value of ``metadata``.
    ///
    /// - Parameter key: The key of the value.
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Opens ``discarded`` when the message of `event` is one of
    /// ``discardMessages``, and opens ``applied`` when it is
    /// ``appliedMessage``.
    ///
    /// - Parameter event: The record.
    func log(event: LogEvent) {
        let message = event.message.description
        if Self.discardMessages.contains(message) {
            discarded.open()
        }
        if message == Self.appliedMessage {
            applied.open()
        }
    }
}
