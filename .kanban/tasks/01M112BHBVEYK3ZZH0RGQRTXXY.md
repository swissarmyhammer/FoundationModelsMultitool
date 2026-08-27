---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11q9192rt3c8vs02qzt8z5c
  text: |-
    ### research — done

    - The source is 10 files, 1,462 lines. `ScriptedServer.swift` is the actor; the four extension files add tools. `ServerMode.swift` parses `--mode`. `main.swift` is a 5-line stdio wrapper.
    - `MCPServer` is not in this package yet (task ^832pg8r). So `connectedServer(over: .inMemory)` returns the connected `MCP.Client` for now. The card names the function; the return type changes when `MCPServer` lands.
    - The test target here has no `TestServerCLILocator`. The port puts one in `Tests/FoundationModelsMultitoolTests/Support/TestServerLocator.swift`, with the `..` path check of the source's `ProductsDirectoryPathValidation` folded in, because this package has one reader of it.
    - `TestPoll` (`Fixtures/PollFixtures.swift`) is the one poll of the test target. The ported self-tests use it in place of the source's private `poll` helper.
    - The rules to obey up front: every public item documented; every numeric literal named (swiftlint `no_magic_numbers`, tests included); no unstructured leaks; `// periphery:ignore` with a reason line above it for assign-only properties.
    - Of the four deferred `StdioServerProcessTests` cases, two need only the test server: the handshake-and-tool-call case (over a raw `MCP.Client`), and the external-kill case reduced to its `F_SETNOSIGPIPE` claim (a write after the child dies throws, and does not signal the host). The identity case and the reconnect half wait for `MCPServer`.
    - The swift-sdk here is 0.12.1, the same as the source package, so the `requestElicitation(message:url:elicitationId:)` and `ElicitationCompleteNotification` API match.
  timestamp: 2026-08-27T13:41:44.866246+00:00
- actor: claude-code
  id: 01m11qyhq75287djjwg9j8xw8f
  text: |-
    ### implement — changed
    - evidence: 17 files — Package.swift, IntegrationTests/Package.swift, Tests/Support/MCPTestServer/{ScriptedServer,ScriptedTool,JSONSchemaBuilder,FlakyConnectTransport,EchoTool,LoopbackTools,CatalogShowcaseTool,DynamicToolsetScenario,FilesystemToolKit,ServerMode}.swift, Tests/Support/mcp-test-server/main.swift, Tests/FoundationModelsMultitoolTests/{ScriptedServerSelfTests,ServerModeTests}.swift, Tests/FoundationModelsMultitoolTests/Support/{MCPTestSupport,TestServerLocator}.swift, Tests/FoundationModelsMultitoolTests/StdioServerProcessTests.swift
    - checks: `swift build --build-tests` clean; `swift build --product mcp-test-server` clean; `swift test` 1166 tests in 83 suites pass; `swift test --filter 'ScriptedServerSelf|ServerMode|StdioServerProcessTests'` 42 tests pass; the binary answers `initialize` and `tools/list` over stdio in `--mode loopback` (echo, elicitEcho, elicitURL); `swift build --package-path IntegrationTests --build-tests` clean with a probe file that imports `MCPTestServer` (probe removed after the build); swiftlint `missing_docs` + `no_magic_numbers` over the new files: 0 findings; periphery with `--retain-public`: 0 findings in this package.
    - decisions: `connectedServer(to:over:clientName:capabilities:)` returns the connected `MCP.Client` until `MCPServer` (^832pg8r) lands; `ServerMode.loopback` is the new case; `DynamicToolsetScenario` holds its three stages as one table; `TestServerLocator` folds the source's path validation in as private helpers.
    - next: /test, then /commit, then /review
  timestamp: 2026-08-27T13:53:29.831788+00:00
- actor: claude-code
  id: 01m11rjxd3f2shggkkzd69pvqn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (8f3eee7) — 0 findings, 0 confirmed, 1 refuted; 18 files reviewed, 2 `.kanban/` files excluded by `.reviewignore`
    - next: task moves to done
  timestamp: 2026-08-27T14:04:37.155399+00:00
- actor: claude-code
  id: 01m11rk01hzk53g7znra1bwmfx
  text: |-
    ### finish iteration 1 — review clean, task done
    - implement: changed — 17 files (the MCPTestServer library and mcp-test-server executable under Tests/Support/, the two manifests, the ported suites, MCPTestSupport, TestServerLocator, and two cases in StdioServerProcessTests)
    - test: green — swift test 1166 tests in 83 suites passed, 0 failed, 0 skipped; 0 warnings from this package
    - commit: 8f3eee7
    - review: clean — 0 findings over HEAD~1..HEAD
  timestamp: 2026-08-27T14:04:39.857596+00:00
depends_on:
- 01M11286356T1VMGHBSMF9V7W5
position_column: done
position_ordinal: ff8f80
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
- [x] `ScriptedServer` serves `initialize`, `tools/list`, `tools/call`, `notifications/progress`, `notifications/tools/list_changed`, and `elicitation/create`, as the source does.
- [x] `addLoopbackTools()` registers `echo`, `elicitEcho`, and `elicitURL` by those names.
- [x] `import MCPTestServer` compiles from `IntegrationTests/`.
- [x] `swift build --product mcp-test-server` gives an executable that answers `initialize` over stdio and serves the loopback mode.
- [x] `swift build` succeeds.

## Tests
- [x] Port `ScriptedServerSelfTests.swift` and `ServerModeTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Add a case for the loopback `ServerMode`.
- [x] Port the `mcp-test-server` cases that the `StdioServerProcess` task left out, into `StdioServerProcessTests.swift`.
- [x] `swift test --filter ScriptedServerSelfTests` passes.
- [x] `swift test --filter ServerModeTests` passes.

## Workflow
- Use `/tdd` — port the self-tests first, then the server. #eventplan #phase-4