// `MCPServerIdentity` — the stable name of one server connection, and the
// readiness that connection is in.
//
// A behavioral port of the first sixty lines of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`.
// eventplan.md § "Consolidation of the siblings" moves "the `ToolCatalog`"
// into this folder, and the catalog carries these two types: every snapshot
// names the server it describes, and states the readiness the server was in
// when the snapshot was taken. `MCPServer` itself, which owns the connection
// and sets both, stands in `MCPServer.swift`. These two stand in a file of
// their own so that the catalog reads them without the actor.
//
// **Why the identity is a type, and not the server's own name.** A server
// reports a `Server.Info.name` on each `initialize`, and that name can change
// across a reconnect: the host can point the same logical connection at an
// upgraded server. A caller that keys state by server — a routing table, a
// tool cache, a label — needs a key that stays put. `ServerIdentity` is that
// key: `MCPServer` sets it one time, and no reconnect moves it.
//
// **Why the faulted state carries a `String`.** An `Error` value is neither
// `Sendable` nor `Equatable`, and this state must be both: it crosses actor
// boundaries inside a catalog snapshot, and a test asserts on it directly.
//
// **The types are `public`.** `MCPServer` is public, because a host constructs
// and connects it before `buildRegistry()`, and it exposes both: its `state`
// is one of these, and `MCPServerError.notReady(_:)` carries one, so a host
// that reads the state or catches the error names the type.

/// The readiness of an `MCPServer`'s connection to its underlying MCP server.
///
/// There is no "idle" case: a freshly-constructed `MCPServer` starts
/// ``connecting`` (it exists to become connected), and its connect resets to
/// ``connecting`` at the start of every attempt, including a reconnect after
/// ``faulted(_:)`` or after an explicit disconnect. ``disconnected`` is the one
/// state a host reaches on purpose, through `MCPServer.disconnect()`.
public enum MCPServerState: Sendable, Equatable {
    /// The `initialize` handshake has not yet completed successfully.
    case connecting

    /// `initialize` succeeded — the connection is up.
    case ready

    /// The host called `MCPServer.disconnect()`, and no connect ran after it.
    case disconnected

    /// The most recent connection attempt failed — either the transport
    /// handshake or paginated discovery — carrying a human-readable
    /// description of the failure for diagnostics.
    ///
    /// Holds a `String` rather than the originating `Error` because
    /// arbitrary `Error` values are neither `Sendable` nor `Equatable`, and
    /// this state must be both to cross actor boundaries and to be asserted
    /// on directly in tests.
    case faulted(String)
}

/// A stable identifier for one MCP server connection, established once and
/// unaffected by later reconnects.
///
/// A server's self-reported `Server.Info.name` is not guaranteed to stay
/// constant across reconnects (the host might point the same logical
/// connection at a differently-configured or upgraded server instance), but
/// callers that key state by server identity — routing tables, tool caches,
/// UI labels — need that key to stay put across a reconnect. `MCPServer`
/// chooses the name one time, at construction.
public struct ServerIdentity: Sendable, Hashable {
    /// The stable name identifying this server connection.
    public let name: String
}
