import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the connection resilience of `MCPServer`: the backoff-retried
/// connect, its exhaustion, the per-attempt timeout against a transport that
/// hangs, the generation guard against a late attempt, the client-operation
/// queue against a straggler, and the state machine a host reads.
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

    /// How long a test waits for a released, orphaned attempt to run and
    /// discard its result before it asserts — a fixed, bounded interval,
    /// because the whole point is that nothing observable changes.
    private static let orphanedAttemptSettleDelay = Duration.milliseconds(200)

    /// `BackoffPolicy.connectTimeout` of the fresh attempt of
    /// ``freshAttemptWaitsForInFlightStragglerBeforeConnectingItsOwnTransport()``.
    /// It sleeps on a `GatedClock` that the test never opens for this
    /// duration, thus the own timeout of that attempt never ends it, and the
    /// value is arbitrary.
    private static let freshAttemptConnectTimeout = MCPServer.clientConnectStragglerGracePeriod

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

    // MARK: - Helpers

    /// A `MCPServer` named ``serverName`` over the three given clocks, with
    /// every other setting at the default of the public initializer.
    ///
    /// - Parameters:
    ///   - clock: The clock the retry loop sleeps on. Defaults to a
    ///     `ManualClock`, whose sleeps end at once. A test that reads the
    ///     backoff schedule gives its own `ManualClock`.
    ///   - clientQueueClock: The clock each bounded wait of the
    ///     client-operation queue sleeps on. Defaults to a real clock.
    ///   - connectAttemptClock: The clock the per-attempt timeout sleeps on.
    ///     Defaults to a `GatedClock` that no test opens, thus no attempt
    ///     times out, however slow the machine is. A test of the timeout
    ///     gives its own clock (card `^kdtrmhv`: no test checks the speed of
    ///     the machine).
    /// - Returns: The server, not yet connected.
    private func makeServer(
        clock: any Clock<Duration> = ManualClock(),
        clientQueueClock: any Clock<Duration> = ContinuousClock(),
        connectAttemptClock: any Clock<Duration> = GatedClock()
    ) -> MCPServer {
        MCPTestSupport.makeServer(
            name: Self.serverName, clock: clock, clientQueueClock: clientQueueClock,
            connectAttemptClock: connectAttemptClock)
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

    /// Builds a `RespawningTransport` whose first `connect()` succeeds
    /// against a real `ScriptedServer`, and whose every later `connect()` —
    /// every reconnect attempt — hangs for good, the never-resumed
    /// continuation idiom of `HangingTransport`.
    ///
    /// - Parameter counter: Records every `makePair` call, so a test asserts
    ///   how many attempts were made.
    /// - Returns: The transport.
    private func respawningThatHangsAfterFirstConnect(counter: CallCounter) -> RespawningTransport {
        RespawningTransport {
            let attempt = counter.increment()
            if attempt == 1 {
                let (client, server) = await InMemoryTransport.createConnectedPair()
                let scripted = ScriptedServer()
                try await scripted.start(transport: server)
                return (client, scripted)
            }
            return try await withCheckedThrowingContinuation {
                (_: CheckedContinuation<RespawningTransport.Pair, any Error>) in
                // Never resumed: every reconnect attempt after the first
                // hangs, so the schedule advances only by its per-attempt
                // `connectTimeout`, on the clock of the attempt.
            }
        }
    }

    /// Runs one ``oneGatedAttempt`` connect, and ends its timeout only when
    /// the gated step of the attempt is in flight. Then the attempt is always
    /// orphaned, and the connect always throws, however slow the machine is
    /// (card `^kdtrmhv`). A timeout that ended before the gated step began
    /// would skip that step, and leave no orphan to test.
    ///
    /// - Parameters:
    ///   - server: The server to connect. Its attempt clock is `attemptClock`.
    ///   - attemptClock: The clock the timeout of the attempt sleeps on.
    ///   - connect: Starts the connect on `server`.
    ///   - inFlight: Whether the gated step of the attempt was called.
    private func connectUntilOrphaned(
        _ server: MCPServer, attemptClock: GatedClock,
        connect: @escaping @Sendable () async throws -> Void,
        inFlight: () async -> Bool
    ) async throws {
        let connecting = Task { try await connect() }
        try await TestPoll.waitUntil("the gated step of the attempt is in flight", inFlight)
        attemptClock.open()
        await #expect(throws: MCPServerError.self) {
            try await connecting.value
        }
        await expectStillConnecting(server)
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
        try await server.connect(via: flaky, backoffPolicy: policy)

        #expect(await server.state == .ready)
        #expect(await flaky.connectAttempts == Self.thirdAttempt)
        #expect(
            clock.recordedSleeps == [
                Self.scheduleBaseDelay, Self.scheduleBaseDelay * Self.backoffDoublingFactor,
            ])
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

        do {
            try await server.connect(via: flaky, backoffPolicy: policy)
            Issue.record("expected connect(via:backoffPolicy:) to throw")
        } catch let MCPServerError.backoffExhausted(serverName, attempts, _) {
            #expect(serverName == Self.serverName)
            #expect(attempts == Self.exhaustionMaxAttempts)
        } catch {
            Issue.record("expected MCPServerError.backoffExhausted, got \(error)")
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
    /// abandoned attempt hangs, and the hang guard fails the test. The test
    /// reads no real time (card `^tm4x2hp`: no test checks the speed of the
    /// machine).
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func connectAttemptTimeoutEndsTheAttemptEvenWhenTransportHangs() async throws {
        let hanging = HangingTransport()
        let policy = BackoffPolicy(
            connectTimeout: Self.hangingConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        let connecting = Task { try await server.connect(via: hanging, backoffPolicy: policy) }
        try await TestPoll.waitUntil("the attempt armed its timeout") { !attemptClock.recordedSleeps.isEmpty }
        attemptClock.open()

        await #expect(throws: MCPServerError.self) {
            try await connecting.value
        }
        #expect(attemptClock.recordedSleeps == [Self.hangingConnectTimeout])
    }

    /// The gate holds the attempt in its connect, and the test ends the
    /// timeout of the attempt only then. Thus the timeout always wins, however
    /// slow the machine is.
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func lateResolvingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let gated = GatedConnectTransport(wrapping: clientTransport)
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        // The gate stays closed past connectTimeout, so this attempt times
        // out and backoff is exhausted while the orphaned attempt is still
        // blocked in the background.
        try await connectUntilOrphaned(server, attemptClock: attemptClock) {
            try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
        } inFlight: {
            await gated.connectWasCalled
        }

        // Now let the orphaned attempt succeed, and give it time to run.
        await gated.release()
        try await Task.sleep(for: Self.orphanedAttemptSettleDelay)

        // The late success was discarded: no identity, and not ready.
        #expect(await server.identity == nil)
        #expect(await server.state != .ready)
        withExtendedLifetime(scripted) {}
    }

    /// The sibling of ``lateResolvingAttemptAfterExhaustionIsDiscarded()``
    /// for the other stale-generation guard — the one in the `catch` block,
    /// which discards a late FAILURE. The wrapped `FlakyConnectTransport`
    /// makes the now-late attempt fail its handshake instead of succeeding,
    /// so this proves the late failure never reaches `.faulted` either.
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func lateFailingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let flaky = FlakyConnectTransport(wrapping: clientTransport, failingConnectAttempts: 1)
        let gated = GatedConnectTransport(wrapping: flaky)
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        try await connectUntilOrphaned(server, attemptClock: attemptClock) {
            try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
        } inFlight: {
            await gated.connectWasCalled
        }

        // Now let the orphaned attempt fail its handshake.
        await gated.release()
        try await Task.sleep(for: Self.orphanedAttemptSettleDelay)

        // The late failure was discarded too: the state stays where the
        // reported exhaustion left it, and is not overwritten with `.faulted`.
        #expect(await server.state == .connecting)
        withExtendedLifetime(scripted) {}
    }

    /// Closes the window between `factory()` returning and
    /// `client.connect(transport:)` being called on its result: an attempt a
    /// newer one already superseded must never hand its factory-built
    /// transport to the client, and must release the transport instead.
    /// Only a gated FACTORY reaches this window — by the time a gated
    /// transport opens, the factory already returned.
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func lateResolvingFactoryAfterExhaustionDisposesAbandonedTransport() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let spy = DisposableSpyTransport(wrapping: clientTransport)
        let gatedFactory = GatedTransportFactory { spy }
        let attemptClock = GatedClock()
        let server = makeServer(clock: ManualClock(), connectAttemptClock: attemptClock)

        try await connectUntilOrphaned(server, attemptClock: attemptClock) {
            try await server.connect(
                via: { try await gatedFactory.make() }, backoffPolicy: Self.oneGatedAttempt)
        } inFlight: {
            await gatedFactory.makeWasCalled
        }

        // The dispose is the event the abandoned attempt ends with: wait for
        // it, and never for a fixed time.
        await gatedFactory.release()
        try await TestPoll.waitUntil("the abandoned attempt disposed its transport") {
            await spy.disposeWasCalled
        }

        // Never connected — the client race is closed — and disposed — the
        // resource leak is closed.
        #expect(await spy.connectWasCalled == false)
        #expect(await server.identity == nil)
        #expect(await server.state != .ready)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A fresh attempt must wait for an in-flight straggler, not race it

    /// An attempt that passed every generation guard and began connecting
    /// while current can still be inside `client.connect(transport:)` when
    /// its `connectTimeout` elapses, and the abandoned attempt keeps running.
    /// A second, fresh attempt against a distinct transport must wait behind
    /// it under the long connect bound. The load-bearing check is `#require`:
    /// on a server that raced ahead, the release below would let the
    /// straggler install a second message-handling task and crash the test
    /// process.
    ///
    /// The timeout of each attempt sleeps on one `GatedClock`, and each
    /// bounded wait of the queue sleeps on another. The test ends the timeout
    /// of the first attempt only, and never a bound of the queue: thus the
    /// fresh attempt can pass the straggler only when the straggler ends, and
    /// no load can change that (card `^kdtrmhv`).
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func freshAttemptWaitsForInFlightStragglerBeforeConnectingItsOwnTransport() async throws {
        let (straggler, clientTransport1) = try await makeScriptedPair(name: "straggler-server")
        let gated = GatedConnectTransport(wrapping: clientTransport1)
        let queueClock = GatedClock()
        let attemptClock = GatedClock()
        let server = makeServer(clientQueueClock: queueClock, connectAttemptClock: attemptClock)

        let firstAttempt = Task { try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt) }
        // The timeout and the connect run at the same time. Open the timeout
        // only when the connect is in flight, else the timeout can win before
        // the connect is enqueued, and no straggler stays.
        try await TestPoll.waitUntil("the first attempt armed its timeout") { !attemptClock.recordedSleeps.isEmpty }
        try await TestPoll.waitUntil("the first attempt is in connect") { await gated.connectWasCalled }
        attemptClock.open(sleepsOf: Self.gatedConnectTimeout)
        await #expect(throws: MCPServerError.self) {
            try await firstAttempt.value
        }
        await expectStillConnecting(server)

        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let spy = DisposableSpyTransport(wrapping: clientTransport2)
        let freshPolicy = BackoffPolicy(
            connectTimeout: Self.freshAttemptConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let attempt2 = Task { try await server.connect(via: spy, backoffPolicy: freshPolicy) }
        try await TestPoll.waitUntil("the fresh attempt waits behind the straggler") {
            queueClock.recordedSleeps.contains(MCPServer.clientConnectStragglerGracePeriod)
        }

        try #require(await spy.connectWasCalled == false)
        #expect(await server.state != .ready)

        // Release the straggler: its stale success is discarded, and the
        // fresh attempt makes its own connect.
        await gated.release()
        try await attempt2.value

        #expect(await spy.connectWasCalled == true)
        #expect(await server.state == .ready)
        #expect(await server.identity == ServerIdentity(name: Self.serverName))
        queueClock.open()
        attemptClock.open()
        withExtendedLifetime((straggler, fresh)) {}
    }

    /// The `.disconnect` side of the per-predecessor bound of the queue: a
    /// real `client.disconnect()` held in flight, and a fresh connect
    /// enqueued behind it. With no connect unresolved anywhere in the queue,
    /// the short bound applies, and it is safe to proceed once it elapses
    /// even though the predecessor never finishes.
    ///
    /// Each bounded wait of the queue sleeps on a `GatedClock`, thus no bound
    /// can elapse before the test opens the clock, and every bound elapses
    /// when it does. The clock records the bound each wait chose, which is
    /// what proves the short bound and not the long one. The fresh transport
    /// holds its own connect at a gate, thus the fresh attempt cannot reach
    /// `.ready` before the first disconnect wrote `.disconnected`.
    @Test func freshOperationWaitsForInFlightDisconnectStragglerBoundedByDisconnectGracePeriod()
        async throws
    {
        let (initial, clientTransport1) = try await makeScriptedPair(name: "initial-server")
        let gatedDisconnect = GatedDisconnectTransport(wrapping: clientTransport1)
        let queueClock = GatedClock()

        let server = makeServer(clientQueueClock: queueClock)
        try await server.connect(via: gatedDisconnect, backoffPolicy: .default)
        #expect(await server.state == .ready)

        let tailBeforeDisconnect = await server.clientQueueTail
        let firstDisconnect = Task { await server.disconnect() }
        try await TestPoll.waitUntil("the first disconnect entered the client queue") {
            await server.clientQueueTail != tailBeforeDisconnect
        }

        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let gatedConnect = GatedConnectTransport(wrapping: clientTransport2)
        let spy = DisposableSpyTransport(wrapping: gatedConnect)
        let tailBehindDisconnect = await server.clientQueueTail
        let attempt2 = Task { try await server.connect(via: spy, backoffPolicy: .default) }
        try await TestPoll.waitUntil("the fresh attempt entered the client queue") {
            await server.clientQueueTail != tailBehindDisconnect
        }

        // The fresh attempt waits in the queue, and no bound elapsed: it has
        // not raced ahead of the first disconnect.
        #expect(await spy.connectWasCalled == false)

        // Every bound elapses, with the first disconnect still gated: the
        // first disconnect returns, and the fresh attempt proceeds anyway.
        queueClock.open()
        await firstDisconnect.value
        try await TestPoll.waitUntil("the fresh attempt connected its own transport") {
            await spy.connectWasCalled
        }
        await gatedConnect.release()
        try await attempt2.value
        #expect(await server.state == .ready)
        #expect(!queueClock.recordedSleeps.isEmpty)
        #expect(queueClock.recordedSleeps.allSatisfy { $0 == MCPServer.clientDisconnectGracePeriod })

        await gatedDisconnect.release()
        withExtendedLifetime((initial, fresh)) {}
    }

    // MARK: - An explicit connect wins against an in-flight reconnect

    /// The timeout of each connect attempt sleeps on one `GatedClock`, and
    /// each bounded wait of the client-operation queue sleeps on another. No
    /// bound ends before the test opens it, thus the order of the events is
    /// the order the test states, and no load can change it (card
    /// `^kdtrmhv`: no test checks the speed of the machine):
    ///
    /// 1. The reconnect starts its second attempt, which hangs, and the
    ///    attempt arms its timeout.
    /// 2. The explicit `connect(via:)` waits in the queue behind the hung
    ///    attempt, under the straggler bound. The test ends that bound only,
    ///    and the explicit connect reaches `.ready`.
    /// 3. The test ends the timeout of the hung attempt. The reconnect gives
    ///    up and bumps the generation, and its stale result must not move
    ///    the state.
    @Test(.timeLimit(TestHangGuard.timeLimit))
    func explicitConnectDuringInFlightReconnectWins() async throws {
        let counter = CallCounter()
        let respawning = respawningThatHangsAfterFirstConnect(counter: counter)
        let policy = BackoffPolicy(
            connectTimeout: Self.hungReconnectConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let queueClock = GatedClock()
        let attemptClock = GatedClock()
        let server = makeServer(
            clock: ManualClock(), clientQueueClock: queueClock, connectAttemptClock: attemptClock)
        try await server.connect(via: respawning, backoffPolicy: policy)
        #expect(await server.state == .ready)

        await respawning.disconnect()
        let reconnect = Task { try? await server.reconnect() }
        try await TestPoll.waitUntil("the hung second attempt armed its timeout") {
            counter.count == Self.secondAttempt && attemptClock.recordedSleeps.count == Self.secondAttempt
        }

        let (fresh, freshTransport) = try await makeScriptedPair(name: "fresh-server")
        let explicitConnect = Task { try await server.connect(via: freshTransport) }
        try await TestPoll.waitUntil("the explicit connect waits behind the hung attempt") {
            queueClock.recordedSleeps.contains(MCPServer.clientConnectStragglerGracePeriod)
        }
        #expect(await server.state == .connecting)

        queueClock.open(sleepsOf: MCPServer.clientConnectStragglerGracePeriod)
        try await explicitConnect.value
        #expect(await server.state == .ready)

        attemptClock.open()
        _ = await reconnect.value
        #expect(await server.state == .ready)
        #expect(attemptClock.recordedSleeps == [Self.hungReconnectConnectTimeout, Self.hungReconnectConnectTimeout])
        queueClock.open()
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
        #expect(await server.state == .ready)

        let received = try #require(await scripted.receivedClientCapabilities)
        let elicitation = try #require(received.elicitation)
        #expect(elicitation.form != nil)
        #expect(elicitation.url != nil)

        // The client the actor built declares the same, as `@testable` sees.
        let declared = await server.client.capabilities
        #expect(declared.elicitation == elicitation)
    }

    // MARK: - The state machine a host reads

    @Test func disconnectMovesStateToDisconnectedAndKeepsIdentity() async throws {
        let scripted = ScriptedServer()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)

        await server.disconnect()

        #expect(await server.state == .disconnected)
        #expect(await server.identity == ServerIdentity(name: Self.serverName))
        await expectWaitUntilReadyThrowsNotReady(server, carrying: .disconnected)
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

        let connecting = Task { try await server.connect(via: gated) }
        let waiting = Task { try await server.waitUntilReady() }

        await gated.release()
        try await connecting.value
        try await waiting.value

        #expect(await server.state == .ready)
        withExtendedLifetime(scripted) {}
    }
}
