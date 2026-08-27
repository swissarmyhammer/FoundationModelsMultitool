// `RespawningTransport` — a transport that builds a fresh server pair on
// every `connect()`.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/RespawningTransport.swift`.

import struct Foundation.Data
import Logging
import MCP
import MCPTestServer

/// A `Transport` whose ``connect()`` always builds a brand-new (client
/// transport, `ScriptedServer`) pair through `makePair` and delegates to it —
/// a transport that respawns or redials on every connect attempt, the way a
/// real stdio (subprocess) or HTTP (session) transport does on a reconnect.
///
/// Different from `FlakyConnectTransport` on purpose: to reuse the same
/// `MCP.Server` / `MCP.Client` pair across a reconnect does not work against a
/// real sdk server, because the `Initialize` handler of `Server` rejects a
/// second `initialize` on an already-initialized session. A reconnect is a
/// new session from the point of view of the server, so this double models
/// that: every ``connect()`` gets its own fresh, never-initialized
/// `ScriptedServer`.
///
/// ``disconnect()`` severs the connection of the CURRENT pair — a test calls
/// it directly to script a transport drop, and the next ``connect()`` — the
/// reconnect of `MCPServer` — swaps in a fresh pair.
actor RespawningTransport: Transport {
    /// One client transport and the scripted server on its far end.
    typealias Pair = (client: any Transport, server: ScriptedServer)

    /// Builds and starts a fresh pair — one call per ``connect()``.
    private let makePair: @Sendable () async throws -> Pair

    /// The client end of the active pair.
    private var current: (any Transport)?

    /// The receive stream of the active pair, cached by ``connect()``.
    private var currentReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The `ScriptedServer` of the active pair, retained so it is not
    /// deallocated under its own in-flight handlers — never read back.
    private var currentServer: ScriptedServer?

    /// The logger of this double — a no-op.
    nonisolated let logger = Logger(
        label: "mcp.transport.respawning",
        factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// Creates a respawning transport.
    ///
    /// - Parameter makePair: Builds and starts a fresh (client transport,
    ///   `ScriptedServer`) pair, called one time per ``connect()`` call,
    ///   reconnects included.
    init(makePair: @escaping @Sendable () async throws -> Pair) {
        self.makePair = makePair
    }

    /// A respawning transport whose every ``connect()`` starts the
    /// `ScriptedServer` `makeScripted` builds on the server end of a fresh
    /// `InMemoryTransport` pair, and connects over the client end — the pair
    /// every suite that scripts a transport drop and a reconnect needs.
    ///
    /// - Parameter makeScripted: Builds the scripted server of one connect,
    ///   with every tool it serves already registered.
    /// - Returns: The respawning transport.
    static func servingFreshScriptedServers(
        _ makeScripted: @escaping @Sendable () async -> ScriptedServer
    ) -> RespawningTransport {
        RespawningTransport {
            let (client, server) = await InMemoryTransport.createConnectedPair()
            let scripted = await makeScripted()
            try await scripted.start(transport: server)
            return (client, scripted)
        }
    }

    /// Builds a fresh pair through `makePair`, connects to it, and caches its
    /// receive stream — every call discards whatever pair was active before.
    ///
    /// - Throws: What `makePair` or the `connect()` of the fresh client
    ///   transport throws.
    func connect() async throws {
        let (client, server) = try await makePair()
        try await client.connect()
        current = client
        currentServer = server
        currentReceiveStream = await client.receive()
    }

    /// Severs the connection of the active pair.
    func disconnect() async {
        await current?.disconnect()
    }

    /// Delegates to the `send(_:)` of the active pair.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: `MCPError.internalError` when no pair connected yet;
    ///   otherwise what the `send(_:)` of the active pair throws.
    func send(_ data: Data) async throws {
        guard let current else {
            throw MCPError.internalError("RespawningTransport not connected")
        }
        try await current.send(data)
    }

    /// Returns the receive stream of the active pair, cached by the most
    /// recent ``connect()``.
    ///
    /// - Returns: The cached stream, or a finished empty stream before any
    ///   ``connect()``.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let currentReceiveStream else {
            return AsyncThrowingStream { $0.finish() }
        }
        return currentReceiveStream
    }
}
