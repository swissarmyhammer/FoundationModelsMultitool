// `MCPTestSupport` — the connect boilerplate the MCP suites share.
//
// A behavioral port of the transport-pair and `connectedServer` helpers of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/TestSupport.swift`.
// The helpers for the soft deadline, the call handle and the follow-up tools
// are not ported: the types they name are not in this package.
//
// **Two connected shapes.** `connectedServer(to:over:clientName:capabilities:)`
// returns the connected `MCP.Client`, for a suite that drives the wire
// directly — `ServerModeTests` lists tools, `ScriptedServerSelfTests` calls
// them. `connectedMCPServer(to:over:name:)` returns an `MCPServer` connected
// against the scripted server, for a suite of the server itself.
// `MCPTransportKind.http` is the in-process HTTP loopback of
// `LoopbackHTTPServer`, so one parameterized case runs over both transports.
// `connectedLoopbackMCPServer(over:name:)` builds the scripted server with the
// three loopback tools and connects it, for a suite of the capability.

import FoundationModelsExtras
import Logging
import MCP
import MCPTestServer

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The transport a ``MCPTestSupport/connectedServer(to:over:clientName:capabilities:)``
/// or a ``MCPTestSupport/connectedMCPServer(to:over:name:)`` call connects over.
enum MCPTransportKind {
    /// One end of an `InMemoryTransport.createConnectedPair()` for each side.
    case inMemory

    /// An `HTTPClientTransport` at the endpoint of a `LoopbackHTTPServer`
    /// over the scripted server — HTTP in one process, with no socket.
    ///
    /// The returned transport is a ``LoopbackClosingTransport``. Its
    /// `disconnect()` stops the loopback, after the wrapped transport ends.
    /// So the live SSE stream and the registry entry of `LoopbackHTTPServer`
    /// both end when a test disconnects its `Client` or `MCPServer`. A test
    /// over `.http` owes that disconnect, the same way any well-behaved
    /// caller of a live resource does. The in-memory pair of ``inMemory`` is
    /// never torn down by the helper, and needs no disconnect: it holds no
    /// OS-level resource, unlike a loopback's SSE stream.
    case http
}

/// Shared "connect to a `ScriptedServer`" scaffolding for the MCP suites of
/// this test target, so no suite carries a copy of the same transport-pair
/// setup.
enum MCPTestSupport {
    /// The client version every test client reports.
    private static let clientVersion = "1.0"

    /// Builds a fresh `MCP.Client` for a test, named `name` for readability
    /// in transport-level logs.
    ///
    /// - Parameters:
    ///   - name: The client name to log under — by convention the name of
    ///     the calling suite plus `"TestClient"`.
    ///   - capabilities: The client capabilities to advertise. The default
    ///     advertises none; a test of elicitation passes
    ///     `Client.Capabilities(elicitation: .init())`.
    /// - Returns: The client, not yet connected.
    static func makeClient(name: String, capabilities: Client.Capabilities = .init()) -> Client {
        Client(name: name, version: clientVersion, capabilities: capabilities)
    }

    /// Starts `scripted` on the server end of a transport of `kind`, and
    /// returns the client end, ready for a connect.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server to serve on the far end.
    ///   - kind: The transport to connect over.
    /// - Returns: The client end of the transport.
    /// - Throws: What `ScriptedServer.start(transport:)` or
    ///   `LoopbackHTTPServer.start()` throws. A `.http` transport has no
    ///   timeout: the loopback ends each request on the event of its response.
    static func clientTransport(
        serving scripted: ScriptedServer, over kind: MCPTransportKind
    ) async throws -> any Transport {
        switch kind {
        case .inMemory:
            return try await scripted.startOnInMemoryPair()
        case .http:
            let loopback = LoopbackHTTPServer(serving: scripted)
            let (endpoint, configuration) = try await loopback.start()
            return LoopbackClosingTransport(
                wrapping: HTTPClientTransport(endpoint: endpoint, configuration: configuration),
                stopping: loopback)
        }
    }

    /// Starts `scripted` on the server end of a transport of `kind`, and
    /// returns a client connected — and so already initialized — against
    /// the client end.
    ///
    /// - Important: The caller keeps the `scripted` server alive for the
    ///   whole test: the method handlers of ``ScriptedServer`` capture `self`
    ///   weakly, so a scripted server released after connect answers no
    ///   calls.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server to serve on the far end, with every
    ///     tool a test needs already registered.
    ///   - kind: The transport to connect over.
    ///   - clientName: Forwarded to ``makeClient(name:capabilities:)``.
    ///   - capabilities: Forwarded to ``makeClient(name:capabilities:)``.
    /// - Returns: The connected client.
    /// - Throws: What `ScriptedServer.start(transport:)` or
    ///   `Client.connect(transport:)` throws.
    static func connectedServer(
        to scripted: ScriptedServer,
        over kind: MCPTransportKind,
        clientName: String,
        capabilities: Client.Capabilities = .init()
    ) async throws -> Client {
        let client = makeClient(name: clientName, capabilities: capabilities)
        let transport = try await clientTransport(serving: scripted, over: kind)
        try await closingOnFailure(transport) {
            _ = try await client.connect(transport: transport)
        }
        return client
    }

    /// Runs `connect`, and disconnects `transport` when it throws.
    ///
    /// A `.http` transport is a ``LoopbackClosingTransport`` over a started
    /// `LoopbackHTTPServer`, and that loopback holds the one process-wide gate
    /// of `LoopbackHTTPServer` until its `stop()`. A connect that throws and
    /// leaves the transport connected parks every later `.http` connect of the
    /// process for ever, which reports as a hang of the whole run and not as
    /// the one failure that caused it.
    ///
    /// - Parameters:
    ///   - transport: The transport to disconnect when the connect throws.
    ///   - connect: The connect to run.
    /// - Throws: What `connect` throws.
    private static func closingOnFailure(
        _ transport: any Transport, _ connect: () async throws -> Void
    ) async throws {
        do {
            try await connect()
        } catch {
            await transport.disconnect()
            throw error
        }
    }

    /// Builds an `MCPServer` named `name` for a test, not yet connected.
    ///
    /// Each setting has the default of the public initializer, except
    /// `clock`, `connectAttemptClock`, `callTimeoutClock` and `userPresence`.
    /// The public initializer has no default for `userPresence`, so that a
    /// host must choose. This test helper gives `.interactive` as a
    /// test-only default, because most suites test a session where a
    /// person can answer. A suite of a headless session passes `.headless`.
    /// The default of `clock` is a
    /// `ManualClock`. Thus each delay between retries and each coalesce
    /// window ends at once, and no real time passes. The default of
    /// `connectAttemptClock` is a `GatedClock` that no test opens. Thus no
    /// connect attempt and no reconnect attempt of the server times out,
    /// however slow the machine is (card `^zbhjc99`: no test checks the
    /// speed of the machine). A test of the timeout gives its own
    /// `GatedClock`, opens it when the attempt is in flight, and reads the
    /// recorded duration.
    ///
    /// The default of `callTimeoutClock` is also a `GatedClock` that no test
    /// opens. Thus no bare call of the server times out. A test of the
    /// bare-call timeout gives its own clock.
    ///
    /// - Parameters:
    ///   - name: The name of the server, and so its identity.
    ///   - clock: The clock the server sleeps on — between retries, and for
    ///     the `tools/list_changed` coalesce window. Defaults to a
    ///     `ManualClock`, whose sleeps end at once. A test that reads the
    ///     backoff schedule gives its own `ManualClock` and reads
    ///     `recordedSleeps`.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect sleeps on. Defaults to a `GatedClock` that no test opens.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on.
    ///     Defaults to a `GatedClock` that no test opens.
    ///   - callTimeout: The bound of a call made with no ambient
    ///     `ToolContext`. Defaults to `MCPServer.defaultCallTimeout`.
    ///   - renderBudget: The render budget every rendered result of the
    ///     server obeys. Defaults to `RenderBudget.default`.
    ///   - elicitationHandler: The host's answerer for an elicitation that
    ///     arrives under no `ToolContext`. Defaults to `nil`.
    ///   - userPresence: Whether a person is present to answer an
    ///     elicitation. Defaults to `.interactive`, a test-only default: the
    ///     public initializer of `MCPServer` has none.
    ///   - logger: The logger of the server. Defaults to
    ///     `MCPServer.defaultLogger`.
    /// - Returns: The server, not yet connected.
    static func makeServer(
        name: String,
        clock: any Clock<Duration> = ManualClock(),
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        callTimeoutClock: any Clock<Duration> = GatedClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default,
        elicitationHandler: MCPServer.ElicitationHandler? = nil,
        userPresence: UserPresence = .interactive,
        logger: Logger = MCPServer.defaultLogger
    ) -> MCPServer {
        MCPServer(
            name: name,
            version: MCPServer.defaultClientVersion,
            clock: clock,
            connectAttemptClock: connectAttemptClock,
            callTimeoutClock: callTimeoutClock,
            callTimeout: callTimeout,
            renderBudget: renderBudget,
            elicitationHandler: elicitationHandler,
            userPresence: userPresence,
            logger: logger)
    }

    /// Starts `scripted` on the server end of a transport of `kind`, and
    /// returns an `MCPServer` named `name` connected — and so `.ready` —
    /// against the client end.
    ///
    /// - Important: The caller keeps the `scripted` server alive for the
    ///   whole test, as ``connectedServer(to:over:clientName:capabilities:)``
    ///   requires.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server to serve on the far end.
    ///   - kind: The transport to connect over.
    ///   - name: The name of the `MCPServer`, and so its identity.
    ///   - clock: The clock the server sleeps on — between retries, and for
    ///     the `tools/list_changed` coalesce window. Defaults to a
    ///     `ManualClock`, whose sleeps end at once — see
    ///     ``makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect or a reconnect sleeps on. Defaults to a `GatedClock` that
    ///     no test opens — see ``makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on.
    ///     Defaults to a `GatedClock` that no test opens.
    ///   - callTimeout: The bound of a call made with no ambient
    ///     `ToolContext`. Defaults to `MCPServer.defaultCallTimeout`.
    ///   - renderBudget: The render budget every rendered result of the
    ///     server obeys. Defaults to `RenderBudget.default`; a suite of the
    ///     verb passes a tight one.
    ///   - elicitationHandler: The host's answerer for an elicitation that
    ///     arrives under no `ToolContext`. Defaults to `nil`; a suite of the
    ///     bare-session path passes one.
    ///   - userPresence: Whether a person is present to answer an
    ///     elicitation. Defaults to `.interactive`, a test-only default: the
    ///     public initializer of `MCPServer` has none. A suite of a headless
    ///     session passes `.headless`.
    ///   - logger: The logger of the `MCPServer`. Defaults to
    ///     `MCPServer.defaultLogger`; a suite that reads the records of the
    ///     server passes a recording one.
    /// - Returns: The connected server.
    /// - Throws: What `ScriptedServer.start(transport:)` or
    ///   `MCPServer.connect(via:)` throws.
    static func connectedMCPServer(
        to scripted: ScriptedServer,
        over kind: MCPTransportKind,
        name: String,
        clock: any Clock<Duration> = ManualClock(),
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        callTimeoutClock: any Clock<Duration> = GatedClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default,
        elicitationHandler: MCPServer.ElicitationHandler? = nil,
        userPresence: UserPresence = .interactive,
        logger: Logger = MCPServer.defaultLogger
    ) async throws -> MCPServer {
        let server = makeServer(
            name: name, clock: clock, connectAttemptClock: connectAttemptClock,
            callTimeoutClock: callTimeoutClock, callTimeout: callTimeout, renderBudget: renderBudget,
            elicitationHandler: elicitationHandler, userPresence: userPresence, logger: logger)
        let transport = try await clientTransport(serving: scripted, over: kind)
        try await closingOnFailure(transport) {
            try await server.connect(via: transport)
        }
        return server
    }

    /// Starts `scripted` on the server end of an in-memory pair, and returns
    /// an `MCPServer` named `name` connected against the client end through a
    /// ``WireRecordingTransport`` — beside that transport, so a suite of the
    /// session-end sweep reads the order of the wire, and a suite of the
    /// trace propagation reads the `_meta` of each request.
    ///
    /// - Important: The caller keeps the `scripted` server alive for the
    ///   whole test, as ``connectedServer(to:over:clientName:capabilities:)``
    ///   requires.
    ///
    /// - Parameters:
    ///   - scripted: The scripted server to serve on the far end.
    ///   - name: The name of the `MCPServer`, and so its identity.
    ///   - callTimeout: The bound of a call with no ambient context. The
    ///     default is the default of `MCPServer`.
    ///   - logger: The logger of the `MCPServer`. The default is the default
    ///     of `MCPServer`.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect or a reconnect sleeps on. Defaults to a `GatedClock` that
    ///     no test opens — see ``makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on.
    ///     Defaults to a `GatedClock` that no test opens.
    /// - Returns: The connected server, and the recording transport it
    ///   connected over.
    /// - Throws: What `ScriptedServer.startOnInMemoryPair()` or
    ///   `MCPServer.connect(via:)` throws.
    static func connectedRecordingMCPServer(
        to scripted: ScriptedServer, name: String,
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        logger: Logger = MCPServer.defaultLogger,
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        callTimeoutClock: any Clock<Duration> = GatedClock()
    ) async throws -> (server: MCPServer, wire: WireRecordingTransport) {
        let wire = WireRecordingTransport(wrapping: try await scripted.startOnInMemoryPair())
        let server = makeServer(
            name: name, connectAttemptClock: connectAttemptClock, callTimeoutClock: callTimeoutClock,
            callTimeout: callTimeout, logger: logger)
        try await server.connect(via: wire)
        return (server, wire)
    }

    /// Builds a fresh `ScriptedServer` that serves `tools`, and returns it
    /// beside an `MCPServer` named `name` connected against it over the
    /// in-memory transport — the shape every suite of the call path and of
    /// the verb starts from.
    ///
    /// - Important: The caller keeps the returned `ScriptedServer` alive for
    ///   the whole test, as ``connectedMCPServer(to:over:name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``
    ///   requires.
    ///
    /// - Parameters:
    ///   - tools: The tools to register before the connect.
    ///   - name: The name of the `MCPServer`, and so its identity.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect or a reconnect sleeps on. Defaults to a `GatedClock` that
    ///     no test opens — see ``makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on.
    ///     Defaults to a `GatedClock` that no test opens.
    ///   - callTimeout: The bound of a bare call of the server. Defaults to
    ///     `MCPServer.defaultCallTimeout`.
    ///   - renderBudget: The render budget of the server. Defaults to
    ///     `RenderBudget.default`.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    static func connectedMCPServer(
        serving tools: [ScriptedTool],
        name: String,
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        callTimeoutClock: any Clock<Duration> = GatedClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer()
        for tool in tools {
            await scripted.addTool(tool)
        }
        let server = try await connectedMCPServer(
            to: scripted, over: .inMemory, name: name, connectAttemptClock: connectAttemptClock,
            callTimeoutClock: callTimeoutClock, callTimeout: callTimeout, renderBudget: renderBudget)
        return (scripted, server)
    }

    /// Builds a fresh `ScriptedServer` that serves the three loopback tools of
    /// `ScriptedServer.addLoopbackTools()`, and returns it beside an
    /// `MCPServer` named `name` connected against it over a transport of
    /// `kind` — the shape a suite of the capability starts from, so one
    /// parameterized case runs over both transports.
    ///
    /// - Important: The caller keeps the returned `ScriptedServer` alive for
    ///   the whole test, as ``connectedMCPServer(to:over:name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``
    ///   requires.
    ///
    /// - Parameters:
    ///   - kind: The transport to connect over.
    ///   - name: The name of the `MCPServer`, and so its identity and the
    ///     noun its verbs render under.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect or a reconnect sleeps on. Defaults to a `GatedClock` that
    ///     no test opens — see ``makeServer(name:clock:connectAttemptClock:callTimeoutClock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``.
    ///   - elicitationHandler: The host's answerer for an elicitation that
    ///     arrives under no `ToolContext`. Defaults to `nil`.
    ///   - userPresence: Whether a person is present to answer an
    ///     elicitation. Defaults to `.interactive`, a test-only default: the
    ///     public initializer of `MCPServer` has none.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    static func connectedLoopbackMCPServer(
        over kind: MCPTransportKind, name: String,
        connectAttemptClock: any Clock<Duration> = GatedClock(),
        elicitationHandler: MCPServer.ElicitationHandler? = nil,
        userPresence: UserPresence = .interactive
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let server = try await connectedMCPServer(
            to: scripted, over: kind, name: name, connectAttemptClock: connectAttemptClock,
            elicitationHandler: elicitationHandler, userPresence: userPresence)
        return (scripted, server)
    }
}
