---
assignees:
- claude-code
depends_on:
- 01M11286356T1VMGHBSMF9V7W5
position_column: todo
position_ordinal: '8680'
title: Port the MCP scripted test server as a test-support product (in-memory and stdio)
---
## What
The MCP tests run against a scripted server. Port it with its two transports (in-memory, stdio). The in-process HTTP loopback is the next task.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/MCPTestServer/` (1,462 lines). The types: `ScriptedServer` (an actor over `MCP.Server`), `ScriptedTool`, `FlakyConnectTransport`, `JSONSchemaBuilder`, `ServerMode`, and `VirtualFilesystem` (in `FilesystemToolKit.swift`). The files `EchoTool.swift`, `DynamicToolsetScenario.swift`, `CatalogShowcaseTool.swift`, and `FilesystemToolKit.swift` are each an `extension ScriptedServer`; port them as files. And `Sources/MCPTestServerCLI/main.swift`.
- Target: a new library target `MCPTestServer` at `Tests/Support/MCPTestServer/` and a new executable target `mcp-test-server` at `Tests/Support/mcp-test-server/main.swift`. **Declare both as products** in `Package.swift`, with a doc comment that says they are test support: `IntegrationTests/` is a separate package that reaches this one through `.package(path: "..")`, and it can import products only. The unit test target depends on `MCPTestServer`.
- **Loopback tools.** Three names that later tasks cite. Two are new names this task coins; say so in the doc comments:
  - `echo` — `ScriptedServer.addEchoTool(named:description:)` (exists; default name `echo`).
  - `elicitEcho` — `addElicitingTool(named:message:requestedSchema:preElicitationDelay:postElicitationStall:)` (exists, ScriptedServer.swift:617) registered under the name `elicitEcho`: elicits a form mid-call and reflects the answer in its result.
  - `elicitURL` — `addURLElicitingTool(named:message:url:elicitationId:)` registered under the name `elicitURL`: the three-message URL flow. `ScriptedServer.sendElicitationComplete(elicitationId:)` (line 702) is the helper that ends it.
  Add `ScriptedServer.addLoopbackTools()` that registers all three at once.
- Add a `ServerMode` case for the executable that serves the three loopback tools over stdio, so a gated case in `IntegrationTests/` that cannot script in-process still reaches `elicitEcho`.
- Port `TestSupport.swift` helpers that the MCP suites share (in-memory transport pair, `connectedServer(...)`) into `Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift`, as `connectedServer(over: .inMemory)` with the enum open for `.http` (next task). Leave out helpers for `CallWait`, `CallHandle`, and the follow-up tools.
- Keep `swift-log` out of this package's own targets. The sdk's `Server` takes a `Logging.Logger`; pass a `Logger(label:)` from the transitive `swift-log` the sdk brings, and do not declare it as a dependency of the library target.

## Acceptance Criteria
- [ ] `ScriptedServer` serves `initialize`, `tools/list`, `tools/call`, `notifications/progress`, `notifications/tools/list_changed`, and `elicitation/create`, as the source does.
- [ ] `addLoopbackTools()` registers `echo`, `elicitEcho`, and `elicitURL` by those names.
- [ ] `import MCPTestServer` compiles from `IntegrationTests/`.
- [ ] `swift build --product mcp-test-server` gives an executable that answers `initialize` over stdio and serves the loopback mode.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `ScriptedServerSelfTests.swift` and `ServerModeTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Add a case for the loopback `ServerMode`.
- [ ] Port the `mcp-test-server` cases that the `StdioServerProcess` task left out, into `StdioServerProcessTests.swift`.
- [ ] `swift test --filter ScriptedServerSelfTests` passes.
- [ ] `swift test --filter ServerModeTests` passes.

## Workflow
- Use `/tdd` — port the self-tests first, then the server. #eventplan #phase-4