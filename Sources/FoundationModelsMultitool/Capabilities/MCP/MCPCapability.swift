// `MCPCapability` — the `Capability` of one connected MCP server: the name of
// the server as the noun, and one `MCPTool` for each tool of its catalog.
//
// eventplan.md § "Consolidation of the siblings": "MCP (`Capabilities/MCP`)
// gets `MCPServer`, `StdioServerProcess`, the `SchemaConverter` /
// `GeneratedContentCodec` pair, `ToolContentRenderer` with its
// `RenderBudget`, and the `ToolCatalog`. Each connected server registers as
// its own top-level group: `tools.github.createIssue`, never
// `tools.mcp.github.createIssue`. The model must not see the transport."
//
// **One capability for each server.** eventplan.md § "The capability
// contract" names the short form: "The modules are opt-in: `withShell()`,
// `withFiles()`, and `withMCP(servers:)`." `MultiTool.Builder.withMCP(servers:)`
// builds one of these for each server, in order, and registers each through
// `withCapability(_:)`. Thus a server claims its own noun, and a second
// registration under that noun — a server named `files` beside the files
// capability — is the `.duplicateNoun` failure of `buildRegistry()`, as for
// any other capability. No code here decides that.
//
// **The capability awaits readiness, and it does not connect.** eventplan.md:
// "Servers connect before `buildRegistry()`." The host connects the server;
// `init(server:)` waits for `.ready` through `MCPServer.waitUntilReady()` and
// then reads the catalog one time. A server that can no longer reach
// `.ready` makes the initializer throw `MCPServerError.notReady`, so a host
// never registers an empty group for a server that is down.
//
// **The files that stand in this folder:**
//
// - `SchemaConverter.swift`, `GeneratedContentCodec.swift` and
//   `Value+ScalarString.swift` — a JSON Schema from `tools/list` becomes a
//   `GenerationSchema`, and the model's `GeneratedContent` becomes the
//   `[String: MCP.Value]` of `tools/call`.
// - `ToolContentRenderer.swift` and `RenderBudget.swift` — a `CallTool.Result`
//   becomes the one string the model reads.
// - `MCPToolCatalog.swift` and `MCPServerIdentity.swift` — the catalog of a
//   server's tools, and the identity and state the catalog carries.
// - `StdioServerProcess.swift` — the stdio transport over a server
//   subprocess registered into `ProcessRegistry.global`, and
//   `TransportContracts.swift` — the two contracts a transport states to the
//   server: a permanent failure, and a resource to release.
// - `MCPServer.swift`, `MCPServer+Connection.swift` and
//   `MCPServer+ClientQueue.swift` — the connected server: its state, its
//   connect, reconnect and disconnect, and the queue that serializes its
//   client operations. `BackoffPolicy.swift` holds the retry schedule, the
//   transport factory and the errors of the connect path, and
//   `SingleResume.swift` the one-resumption race both extensions use.
// - `MCPServer+Discovery.swift` and `MCPServer+LiveCatalog.swift` — the
//   paginated `tools/list` of a connect, and the coalesced re-list a
//   `tools/list_changed` burst starts.
// - `MCPServer+Call.swift` — `call(name:arguments:)` on the run plane of
//   Router: progress to the ambient `ToolContext`, cancellation to the wire,
//   a transport drop as `MCPServerError.lost`. `DropObservingTransport.swift`
//   is the transport the client connects over, which reports that drop.
// - `MCPTool.swift` — the plain synchronous `Tool` that one server verb
//   renders as.
//
// **Each file logs with `os.Logger`**, as `MultiTool.swift` does. The `MCP`
// module brings `swift-log` transitively for its own use. Two files of this
// folder import it: `StdioServerProcess.swift` and
// `DropObservingTransport.swift` each name `Logging.Logger` as the type the
// `Transport` protocol requires, and each logs nothing through it — see
// `mcpPackage` in `Package.swift`.

import FoundationModels
import MCP

/// The capability of one connected `MCPServer`: the name of the server as
/// the noun, and one verb for each tool of the server's catalog.
///
/// eventplan.md § "Registration of capabilities": "MCP obeys the same
/// grammar. The server is the noun, and the tool is the verb
/// (`tools.github.createIssue`)." The noun is the server's
/// `ServerIdentity.name`, so the path the model calls never names the
/// transport.
///
/// ```swift
/// let github = MCPServer(name: "github")
/// try await github.connect(via: transport)
///
/// let registry = try await MultiTool.Builder()
///     .withMCP(servers: [github])       // tools.github.<tool>, one for each catalog entry
///     .buildRegistry()
/// ```
///
/// A value: the noun and the tools are read one time, at construction, from
/// the catalog the server holds then. A later `tools/list_changed` re-list
/// moves the server's catalog and not this value; the rebuild-and-swap of
/// the registry is the reader of that change, through ``refreshed()``.
public struct MCPCapability: Capability {
    /// The name of the server — its `ServerIdentity.name` — which is the
    /// first segment of every `tools.<noun>.<verb>` path of this server.
    public let noun: String

    /// One `MCPTool` for each entry of the server's catalog, in `tools/list`
    /// page order. Each tool gives its own verb through `Tool.name`.
    public let tools: [any FoundationModels.Tool]

    /// The server the catalog was read from, kept so ``refreshed()`` can read
    /// its current catalog again.
    let server: MCPServer

    /// A new capability of the same server, read from the catalog the server
    /// holds now — the read a registry rebuild makes.
    ///
    /// - Returns: the capability of the current catalog.
    /// - Throws: what ``init(server:)`` throws.
    func refreshed() async throws -> MCPCapability {
        try await MCPCapability(server: server)
    }

    /// Creates the capability of `server` once the server is ready.
    ///
    /// Awaits `MCPServer.waitUntilReady()`, then reads the server's current
    /// catalog. The host connects the server before this call; this
    /// initializer never connects.
    ///
    /// - Parameter server: The server the host connected.
    /// - Throws: `MCPServerError.notReady(_:)` when `server` is `.faulted` or
    ///   `.disconnected`, and so cannot reach `.ready` without a new connect.
    public init(server: MCPServer) async throws {
        try await server.waitUntilReady()
        let catalog = try await server.catalog
        self.noun = catalog.identity.name
        self.tools = catalog.tools.map { MCPTool(entry: $0, server: server) }
        self.server = server
    }
}
