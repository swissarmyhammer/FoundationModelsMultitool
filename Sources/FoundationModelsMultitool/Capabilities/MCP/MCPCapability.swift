// `MCPCapability` — the folder of the MCP capability, and the file its type
// will stand in.
//
// eventplan.md § "Consolidation of the siblings": "MCP (`Capabilities/MCP`)
// gets `MCPServer`, `StdioServerProcess`, the `SchemaConverter` /
// `GeneratedContentCodec` pair, `ToolContentRenderer` with its
// `RenderBudget`, and the `ToolCatalog`. Each connected server registers as
// its own top-level group: `tools.github.createIssue`, never
// `tools.mcp.github.createIssue`. The model must not see the transport."
//
// **This file holds no type yet.** It opens the folder and it links the `MCP`
// wire module into the library target, so the dated phase-4 note of
// eventplan.md § "Phases" stands before the files it governs. The type
// `MCPCapability` — the `Capability` conformer a host registers through
// `MultiTool.Builder.withMCP(servers:)`, the short form of
// `withCapability(MCPCapability(...))` — comes in a later task.
//
// **The files that stand in this folder, and the files that later tasks add:**
//
// - `SchemaConverter.swift`, `GeneratedContentCodec.swift` and
//   `Value+ScalarString.swift` — a JSON Schema from `tools/list` becomes a
//   `GenerationSchema`, and the model's `GeneratedContent` becomes the
//   `[String: MCP.Value]` of `tools/call`. These three are ported.
// - `ToolContentRenderer.swift` and `RenderBudget.swift` — a `CallTool.Result`
//   becomes the one string the model reads.
// - `MCPToolCatalog.swift` and `MCPServerIdentity.swift` — the catalog of a
//   server's tools, and the identity and state the catalog carries.
// - `StdioServerProcess.swift` — the stdio transport over a server
//   subprocess registered into `ProcessRegistry.global`, and
//   `TransportContracts.swift` — the two contracts a transport states to the
//   server: a permanent failure, and a resource to release. Both are ported.
// - `MCPServer.swift`, `MCPServer+Connection.swift` and
//   `MCPServer+ClientQueue.swift` — the connected server: its state, its
//   connect, reconnect and disconnect, and the queue that serializes its
//   client operations. `BackoffPolicy.swift` holds the retry schedule, the
//   transport factory and the errors of the connect path, and
//   `SingleResume.swift` the one-resumption race both extensions use. The
//   host handler that a bare `LanguageModelSession` sends elicitation to
//   comes with the elicitation task.
// - `MCPTool.swift` — the plain synchronous `Tool` that one server verb
//   renders as.
//
// **Each file logs with `os.Logger`**, as `MultiTool.swift` does. The `MCP`
// module brings `swift-log` transitively for its own use. One file of this
// folder imports it: `StdioServerProcess.swift` names `Logging.Logger` as the
// type the `Transport` protocol requires, and logs nothing through it — see
// `mcpPackage` in `Package.swift`.

import MCP
