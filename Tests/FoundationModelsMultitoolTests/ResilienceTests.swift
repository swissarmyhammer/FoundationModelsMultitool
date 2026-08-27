import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

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

    /// The per-attempt timeout of the hanging-transport test — short, because
    /// the test proves it bounds real time.
    private static let hangingConnectTimeout = Duration.milliseconds(50)

    /// The per-attempt timeout every gated test holds its gate closed past.
    private static let gatedConnectTimeout = Duration.milliseconds(30)

    /// The one delay a single-attempt policy never sleeps.
    private static let singleAttemptDelay = Duration.milliseconds(1)

    /// The attempt budget of every single-attempt policy.
    private static let singleAttempt = 1

    /// The upper bound that proves the hanging-transport test returned on
    /// its `connectTimeout` and not on the transport.
    private static let promptReturnBound = Duration.seconds(5)

    /// How long a test waits for a released, orphaned attempt to run and
    /// discard its result before it asserts — a fixed, bounded interval,
    /// because the whole point is that nothing observable changes.
    private static let orphanedAttemptSettleDelay = Duration.milliseconds(200)

    /// `BackoffPolicy.connectTimeout` of the fresh attempt of
    /// ``freshAttemptWaitsForInFlightStragglerBeforeConnectingItsOwnTransport()``
    /// — equal to `MCPServer.clientConnectStragglerGracePeriod` on purpose,
    /// so the own timeout of that attempt is never the reason it gives up
    /// before the bounded wait of the queue would.
    private static let freshAttemptConnectTimeout = MCPServer.clientConnectStragglerGracePeriod

    /// How long that test waits before it checks that the fresh attempt has
    /// not raced ahead of the straggler: past the short disconnect bound, so
    /// a wrongly applied short bound shows, and well under the long connect
    /// bound, so the check runs before that wait could time out.
    private static let stragglerNotYetRacedAheadCheckDelay = Duration.milliseconds(800)

    /// How long the disconnect-straggler test waits before its first check —
    /// well under `MCPServer.clientDisconnectGracePeriod`.
    private static let disconnectStragglerNotYetRacedAheadCheckDelay = Duration.milliseconds(200)

    /// How much longer that test waits before its second check — added to the
    /// first delay, the wait lands past `MCPServer.clientDisconnectGracePeriod`,
    /// which proves the wait behind a disconnect predecessor is bounded by
    /// the short constant and not the long one.
    private static let disconnectStragglerHasProceededCheckDelay = Duration.milliseconds(600)

    /// The per-attempt timeout of the in-flight reconnect test: long enough
    /// for the explicit connect to bump the generation before the hung
    /// reconnect attempt is timed out, short enough for the test to run
    /// fast.
    private static let hungReconnectConnectTimeout = Duration.milliseconds(300)

    /// How long the in-flight reconnect test waits after the explicit
    /// connect, so the hung reconnect attempt hits its own timeout and is
    /// discarded in the background.
    private static let hungReconnectDiscardDelay = Duration.milliseconds(600)

    /// The attempt count a respawning transport reaches once its reconnect
    /// started: the first connect, plus one reconnect attempt.
    private static let secondAttempt = 2

    // MARK: - Helpers

    /// A `MCPServer` named ``serverName`` over `clock`.
    ///
    /// - Parameter clock: The clock the retry loop sleeps on. Defaults to a
    ///   real clock, for a test that exercises no backoff delay.
    /// - Returns: The server, not yet connected.
    private func makeServer(clock: any Clock<Duration> = ContinuousClock()) -> MCPServer {
        MCPServer(name: Self.serverName, clock: clock)
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
                // `connectTimeout` in real wall-clock time.
            }
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

    // MARK: - Per-attempt timeout bounds real wall-clock time

    @Test func connectAttemptTimeoutBoundsRealWallClockTimeEvenWhenTransportHangs() async throws {
        let hanging = HangingTransport()
        let policy = BackoffPolicy(
            connectTimeout: Self.hangingConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let server = makeServer(clock: ManualClock())

        let start = ContinuousClock.now
        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: hanging, backoffPolicy: policy)
        }
        let elapsed = ContinuousClock.now - start

        // The `connect()` of the hanging transport never returns, so this
        // proves the retry loop returned on `connectTimeout` and did not
        // block on the abandoned attempt.
        #expect(elapsed < Self.promptReturnBound)
    }

    @Test func lateResolvingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let gated = GatedConnectTransport(wrapping: clientTransport)
        let server = makeServer(clock: ManualClock())

        // The gate stays closed past connectTimeout, so this attempt times
        // out and backoff is exhausted while the orphaned attempt is still
        // blocked in the background.
        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
        }
        await expectStillConnecting(server)

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
    @Test func lateFailingAttemptAfterExhaustionIsDiscarded() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let flaky = FlakyConnectTransport(wrapping: clientTransport, failingConnectAttempts: 1)
        let gated = GatedConnectTransport(wrapping: flaky)
        let server = makeServer(clock: ManualClock())

        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
        }
        await expectStillConnecting(server)

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
    @Test func lateResolvingFactoryAfterExhaustionDisposesAbandonedTransport() async throws {
        let (scripted, clientTransport) = try await makeScriptedPair()
        let spy = DisposableSpyTransport(wrapping: clientTransport)
        let gatedFactory = GatedTransportFactory { spy }
        let server = makeServer(clock: ManualClock())

        await #expect(throws: MCPServerError.self) {
            try await server.connect(
                via: { try await gatedFactory.make() }, backoffPolicy: Self.oneGatedAttempt)
        }
        await expectStillConnecting(server)

        await gatedFactory.release()
        try await Task.sleep(for: Self.orphanedAttemptSettleDelay)

        // Never connected — the client race is closed — and disposed — the
        // resource leak is closed.
        #expect(await spy.connectWasCalled == false)
        #expect(await spy.disposeWasCalled == true)
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
    @Test func freshAttemptWaitsForInFlightStragglerBeforeConnectingItsOwnTransport() async throws {
        let (straggler, clientTransport1) = try await makeScriptedPair(name: "straggler-server")
        let gated = GatedConnectTransport(wrapping: clientTransport1)
        let server = makeServer()

        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: gated, backoffPolicy: Self.oneGatedAttempt)
        }
        await expectStillConnecting(server)

        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let spy = DisposableSpyTransport(wrapping: clientTransport2)
        let freshPolicy = BackoffPolicy(
            connectTimeout: Self.freshAttemptConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let attempt2 = Task { try await server.connect(via: spy, backoffPolicy: freshPolicy) }

        try await Task.sleep(for: Self.stragglerNotYetRacedAheadCheckDelay)

        try #require(await spy.connectWasCalled == false)
        #expect(await server.state != .ready)

        // Release the straggler: its stale success is discarded, and the
        // fresh attempt makes its own connect.
        await gated.release()
        try await attempt2.value

        #expect(await spy.connectWasCalled == true)
        #expect(await server.state == .ready)
        #expect(await server.identity == ServerIdentity(name: Self.serverName))
        withExtendedLifetime((straggler, fresh)) {}
    }

    /// The `.disconnect` side of the per-predecessor bound of the queue: a
    /// real `client.disconnect()` held in flight, and a fresh connect
    /// enqueued behind it. With no connect unresolved anywhere in the queue,
    /// the short bound applies, and it is safe to proceed once it elapses
    /// even though the predecessor never finishes.
    @Test func freshOperationWaitsForInFlightDisconnectStragglerBoundedByDisconnectGracePeriod()
        async throws
    {
        let (initial, clientTransport1) = try await makeScriptedPair(name: "initial-server")
        let gatedDisconnect = GatedDisconnectTransport(wrapping: clientTransport1)

        let server = makeServer()
        try await server.connect(via: gatedDisconnect, backoffPolicy: .default)
        #expect(await server.state == .ready)

        let firstDisconnect = Task { await server.disconnect() }

        let (fresh, clientTransport2) = try await makeScriptedPair(name: "fresh-server")
        let spy = DisposableSpyTransport(wrapping: clientTransport2)
        let attempt2 = Task { try await server.connect(via: spy, backoffPolicy: .default) }

        // Under the short bound: the fresh connect has not raced ahead yet.
        try await Task.sleep(for: Self.disconnectStragglerNotYetRacedAheadCheckDelay)
        #expect(await spy.connectWasCalled == false)

        // Past the short bound, with the first disconnect still gated: the
        // fresh attempt proceeded anyway.
        try await Task.sleep(for: Self.disconnectStragglerHasProceededCheckDelay)
        #expect(await spy.connectWasCalled == true)

        try await attempt2.value
        #expect(await server.state == .ready)

        await gatedDisconnect.release()
        await firstDisconnect.value
        withExtendedLifetime((initial, fresh)) {}
    }

    // MARK: - An explicit connect wins against an in-flight reconnect

    /// - Note: Runs for about `MCPServer.clientConnectStragglerGracePeriod`
    ///   of real time: the explicit `connect(via:)` waits out that bound
    ///   behind the permanently hung reconnect attempt before it makes its
    ///   own `client.connect(transport:)` call. Not a regression when this is
    ///   the slowest test of the suite.
    @Test func explicitConnectDuringInFlightReconnectWins() async throws {
        let counter = CallCounter()
        let respawning = respawningThatHangsAfterFirstConnect(counter: counter)
        let policy = BackoffPolicy(
            connectTimeout: Self.hungReconnectConnectTimeout, baseDelay: Self.singleAttemptDelay,
            maxDelay: Self.singleAttemptDelay, maxAttempts: Self.singleAttempt)
        let server = makeServer()
        try await server.connect(via: respawning, backoffPolicy: policy)
        #expect(await server.state == .ready)

        await respawning.disconnect()
        let reconnect = Task { try? await server.reconnect() }

        // Wait until the reconnect started its hung second attempt before
        // racing an explicit connect against it.
        try await TestPoll.waitUntil("the reconnect started its second attempt") {
            counter.count == Self.secondAttempt
        }

        let (fresh, freshTransport) = try await makeScriptedPair(name: "fresh-server")
        try await server.connect(via: freshTransport)

        #expect(await server.state == .ready)

        // Give the hung reconnect attempt time to hit its own timeout and be
        // discarded; its stale result must not move the state.
        try await Task.sleep(for: Self.hungReconnectDiscardDelay)
        #expect(await server.state == .ready)
        _ = await reconnect.value
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
