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

import MCP
import MCPTestServer

@testable import FoundationModelsMultitool

/// The transport a ``MCPTestSupport/connectedServer(to:over:clientName:capabilities:)``
/// or a ``MCPTestSupport/connectedMCPServer(to:over:name:)`` call connects over.
enum MCPTransportKind {
    /// One end of an `InMemoryTransport.createConnectedPair()` for each side.
    case inMemory

    /// An `HTTPClientTransport` at the endpoint of a `LoopbackHTTPServer`
    /// over the scripted server — HTTP in one process, with no socket.
    ///
    /// The helper never stops the loopback: the registry of
    /// `LoopbackHTTPServer` holds it for the rest of the test process, as
    /// the in-memory pair of ``inMemory`` is never torn down by the helper
    /// either. A test that must stop one builds the `LoopbackHTTPServer`
    /// itself.
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
    ///   `LoopbackHTTPServer.start()` throws.
    static func clientTransport(
        serving scripted: ScriptedServer, over kind: MCPTransportKind
    ) async throws -> any Transport {
        switch kind {
        case .inMemory:
            return try await scripted.startOnInMemoryPair()
        case .http:
            let loopback = LoopbackHTTPServer(serving: scripted)
            let (endpoint, configuration) = try await loopback.start()
            return HTTPClientTransport(endpoint: endpoint, configuration: configuration)
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
        _ = try await client.connect(transport: transport)
        return client
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
    ///     the `tools/list_changed` coalesce window. Defaults to a real
    ///     clock; a suite of the live catalog passes a `ManualClock`.
    ///   - callTimeout: The bound of a call made with no ambient
    ///     `ToolContext`. Defaults to `MCPServer.defaultCallTimeout`; a
    ///     suite of the bare call passes a short one.
    ///   - renderBudget: The render budget every rendered result of the
    ///     server obeys. Defaults to `RenderBudget.default`; a suite of the
    ///     verb passes a tight one.
    /// - Returns: The connected server.
    /// - Throws: What `ScriptedServer.start(transport:)` or
    ///   `MCPServer.connect(via:)` throws.
    static func connectedMCPServer(
        to scripted: ScriptedServer,
        over kind: MCPTransportKind,
        name: String,
        clock: any Clock<Duration> = ContinuousClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default
    ) async throws -> MCPServer {
        let server = MCPServer(
            name: name, clock: clock, callTimeout: callTimeout, renderBudget: renderBudget)
        let transport = try await clientTransport(serving: scripted, over: kind)
        try await server.connect(via: transport)
        return server
    }

    /// Builds a fresh `ScriptedServer` that serves `tools`, and returns it
    /// beside an `MCPServer` named `name` connected against it over the
    /// in-memory transport — the shape every suite of the call path and of
    /// the verb starts from.
    ///
    /// - Important: The caller keeps the returned `ScriptedServer` alive for
    ///   the whole test, as ``connectedMCPServer(to:over:name:clock:callTimeout:renderBudget:)``
    ///   requires.
    ///
    /// - Parameters:
    ///   - tools: The tools to register before the connect.
    ///   - name: The name of the `MCPServer`, and so its identity.
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
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer()
        for tool in tools {
            await scripted.addTool(tool)
        }
        let server = try await connectedMCPServer(
            to: scripted, over: .inMemory, name: name, callTimeout: callTimeout,
            renderBudget: renderBudget)
        return (scripted, server)
    }
}
