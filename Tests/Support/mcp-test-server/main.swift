// `mcp-test-server` — the stdio entry point over `ScriptedServer`.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServerCLI/main.swift`. Test support
// — see `testServerExecutableName` in `Package.swift`. A test that cannot
// script a server in-process spawns this binary through `StdioServerProcess`
// and talks to it over stdio.
//
// `--mode <name>` selects the tool set (see `ServerMode`); no flag at all
// registers the `all` set.

import MCP
import MCPTestServer

/// The server name this executable reports at `initialize`.
let serverName = "mcp-test-server"

/// The server version this executable reports at `initialize`.
let serverVersion = "1.0.0"

let mode = ServerMode.parse(from: CommandLine.arguments)
let server = ScriptedServer(name: serverName, version: serverVersion)
await mode.registerTools(on: server)

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
