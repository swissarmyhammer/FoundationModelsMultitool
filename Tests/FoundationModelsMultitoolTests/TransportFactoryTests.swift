import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the transport FACTORY of `MCPServer`: a factory that throws
/// takes the normal retry schedule, a factory that throws a
/// `NonRetryableConnectError` fails at once, a factory that wraps a flaky
/// transport still passes through the schedule, and `reconnect()` calls the
/// factory again.
///
/// A port of `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/TransportFactoryTests.swift`.
///
/// **One case of the source is not here.**
/// `stdioServerKilledMidRunReconnectsViaRespawnedProcessFactory` asserted on
/// `server.call(toolNamed:)` — the call path this package does not port; a
/// later task rewrites it onto the run plane of Router. The reconnect through
/// a respawned process is proven in `StdioServerProcessTests`, through
/// `reconnect()`.
///
/// `singleInstanceConnectRetainsCurrentBehaviorForReestablishingTransport`
/// is here in a new shape: the source triggered the reconnect through a
/// faulting call, and this port triggers it through `reconnect()`.
@Suite("TransportFactory")
struct TransportFactoryTests {
    /// The name every server of this suite is constructed with.
    private static let serverName = "transport-factory-test-server"

    /// A per-attempt timeout no attempt of this suite reaches.
    private static let generousConnectTimeout = Duration.seconds(10)

    /// The base delay of the exhaustion tests — arbitrary, because they
    /// assert the attempt count and the state, not the timing.
    private static let shortBaseDelay = Duration.milliseconds(10)

    /// The delay cap of the exhaustion tests.
    private static let shortMaxDelay = Duration.seconds(1)

    /// The attempt budget of the always-throwing factory test.
    private static let exhaustionMaxAttempts = 3

    /// The attempt budget of the non-retryable test — larger than the budget
    /// of the exhaustion test on purpose: the one invariant is "no more than
    /// one attempt", and a large budget makes a regression that retried
    /// after all show as a count above one and a non-empty sleep list.
    private static let generousMaxAttempts = 5

    /// How many leading connect attempts the flaky transport fails, so the
    /// third succeeds.
    private static let failingConnectAttempts = 2

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

    /// The factory-call count after one connect and one reconnect.
    private static let connectPlusReconnect = 2

    /// A `MCPServer` named ``serverName`` over `clock`.
    ///
    /// - Parameter clock: The clock the retry loop sleeps on. Defaults to a
    ///   real clock, for a test that exercises no backoff delay.
    /// - Returns: The server, not yet connected.
    private func makeServer(clock: any Clock<Duration> = ContinuousClock()) -> MCPServer {
        MCPServer(name: Self.serverName, clock: clock)
    }

    /// A `RespawningTransport` over a fresh echo `ScriptedServer` per
    /// connect, counting every pair it builds on `counter`.
    ///
    /// - Parameter counter: Records every `makePair` call.
    /// - Returns: The transport.
    private func respawning(counting counter: CallCounter) -> RespawningTransport {
        RespawningTransport {
            counter.increment()
            let (client, server) = await InMemoryTransport.createConnectedPair()
            let scripted = ScriptedServer()
            try await scripted.start(transport: server)
            return (client, scripted)
        }
    }

    // MARK: - A factory that throws exhausts backoff and hard-fails

    @Test func factoryThatAlwaysThrowsExhaustsBackoffAndHardFails() async throws {
        struct FactoryError: Error, Equatable {}

        let counter = CallCounter()
        let factory: TransportFactory = {
            counter.increment()
            throw FactoryError()
        }
        let clock = ManualClock()
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.shortBaseDelay,
            maxDelay: Self.shortMaxDelay, maxAttempts: Self.exhaustionMaxAttempts)
        let server = makeServer(clock: clock)

        await #expect(throws: MCPServerError.self) {
            try await server.connect(via: factory, backoffPolicy: policy)
        }

        // The factory ran one time per attempt — a throwing factory is a
        // connect-attempt failure like any other, not an error that escapes
        // the retry loop.
        #expect(counter.count == Self.exhaustionMaxAttempts)
        guard case .faulted = await server.state else {
            Issue.record("expected .faulted state after exhausted backoff")
            return
        }
    }

    // MARK: - A factory that throws a NonRetryableConnectError fails at once

    /// A factory error that conforms to `NonRetryableConnectError` is a
    /// permanent configuration problem, not a flaky connection: the connect
    /// fails after exactly one attempt, with no backoff delay.
    @Test func factoryThatThrowsANonRetryableConnectErrorFailsImmediately() async throws {
        struct PermanentFactoryError: Error, Equatable, NonRetryableConnectError {}

        let counter = CallCounter()
        let factory: TransportFactory = {
            counter.increment()
            throw PermanentFactoryError()
        }
        let clock = ManualClock()
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.shortBaseDelay,
            maxDelay: Self.shortMaxDelay, maxAttempts: Self.generousMaxAttempts)
        let server = makeServer(clock: clock)

        do {
            try await server.connect(via: factory, backoffPolicy: policy)
            Issue.record("expected connect(via:backoffPolicy:) to throw")
        } catch let error as MCPServerError {
            guard case .connectConfigurationFailed = error else {
                Issue.record("expected .connectConfigurationFailed, got \(error)")
                return
            }
        }

        #expect(counter.count == 1)
        #expect(clock.recordedSleeps.isEmpty)
        guard case .faulted = await server.state else {
            Issue.record("expected .faulted state after a non-retryable connect failure")
            return
        }
    }

    // MARK: - FlakyConnectTransport still passes through the factory path

    @Test func factoryWrappingFlakyConnectTransportSucceedsOnThirdAttempt() async throws {
        let scripted = ScriptedServer()
        let clientTransport = try await MCPTestSupport.clientTransport(
            serving: scripted, over: .inMemory)
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.failingConnectAttempts)
        let clock = ManualClock()
        let policy = BackoffPolicy(
            connectTimeout: Self.generousConnectTimeout, baseDelay: Self.scheduleBaseDelay,
            maxDelay: Self.scheduleMaxDelay, maxAttempts: Self.scheduleMaxAttempts)

        let server = makeServer(clock: clock)
        // The factory returns the same instance on every call: the scripted
        // failure count of `FlakyConnectTransport` is stateful across its
        // `connect()` calls, so the factory mediates every attempt and
        // resolves to the same configured double.
        try await server.connect(via: { flaky }, backoffPolicy: policy)

        #expect(await server.state == .ready)
        #expect(await flaky.connectAttempts == Self.failingConnectAttempts + 1)
        #expect(
            clock.recordedSleeps == [
                Self.scheduleBaseDelay, Self.scheduleBaseDelay * Self.backoffDoublingFactor,
            ])
        withExtendedLifetime(scripted) {}
    }

    // MARK: - reconnect()

    /// The single-instance `connect(via:)` stores `{ transport }` as its
    /// factory, so a `reconnect()` retries the same instance — which works
    /// for a transport that re-establishes itself on every `connect()`.
    @Test func reconnectRetriesTheSameSelfReestablishingTransportInstance() async throws {
        let counter = CallCounter()
        let respawning = respawning(counting: counter)
        let server = makeServer()

        try await server.connect(via: respawning)
        #expect(await server.state == .ready)
        #expect(counter.count == 1)

        await respawning.disconnect()
        try await server.reconnect()

        #expect(await server.state == .ready)
        #expect(counter.count == Self.connectPlusReconnect)
    }

    /// A factory-taking connect stores the factory, so a `reconnect()` calls
    /// it again for a fresh transport.
    @Test func reconnectCallsTheFactoryAgainForAFreshTransport() async throws {
        let counter = CallCounter()
        let holder = ScriptedServerHolder()
        let factory: TransportFactory = {
            counter.increment()
            let scripted = ScriptedServer()
            await holder.retain(scripted)
            return try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory)
        }
        let server = makeServer()

        try await server.connect(via: factory, backoffPolicy: .default)
        #expect(await server.state == .ready)

        try await server.reconnect()

        #expect(await server.state == .ready)
        #expect(counter.count == Self.connectPlusReconnect)
    }

    @Test func reconnectBeforeAnyConnectThrowsNeverConnected() async {
        let server = makeServer()

        do {
            try await server.reconnect()
            Issue.record("expected reconnect() to throw")
        } catch let error as MCPServerError {
            #expect(error == .neverConnected)
        } catch {
            Issue.record("expected MCPServerError.neverConnected, got \(error)")
        }
    }

    /// Keeps every `ScriptedServer` a factory built alive for the life of a
    /// test — the method handlers of a scripted server capture `self`
    /// weakly, so a server released after connect answers nothing.
    private actor ScriptedServerHolder {
        /// The servers retained so far.
        private var servers: [ScriptedServer] = []

        /// Retains `server`.
        ///
        /// - Parameter server: The server to keep alive.
        func retain(_ server: ScriptedServer) {
            servers.append(server)
        }
    }
}
