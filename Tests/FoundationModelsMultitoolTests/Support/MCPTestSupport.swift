// `MCPTestSupport` — the connect boilerplate the MCP suites share.
//
// A behavioral port of the transport-pair and `connectedServer` helpers of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/TestSupport.swift`.
// The helpers for `CallWait`, `CallHandle` and the follow-up tools are not
// ported: the types they name are not in this package.
//
// **The return is the connected `MCP.Client`, not an `MCPServer`.** The
// source returned an `MCPServer` connected against the scripted server.
// `MCPServer` comes in a later task (^832pg8r); until it lands, the
// connected client is the whole client side of the connection, and the
// suites drive it directly. `MCPTransportKind` is open for `.http`, which the
// in-process HTTP loopback task adds.

import MCP
import MCPTestServer

/// The transport a ``MCPTestSupport/connectedServer(to:over:clientName:capabilities:)``
/// call connects over.
enum MCPTransportKind {
    /// One end of an `InMemoryTransport.createConnectedPair()` for each side.
    case inMemory
}

/// Shared "connect a client to a `ScriptedServer`" scaffolding for the MCP
/// suites of this test target, so no suite carries a copy of the same
/// transport-pair setup.
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
        switch kind {
        case .inMemory:
            let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
            try await scripted.start(transport: serverTransport)
            _ = try await client.connect(transport: clientTransport)
        }
        return client
    }
}
