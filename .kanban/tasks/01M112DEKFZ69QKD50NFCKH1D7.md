---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12cx93j05a8xb9jzb36pg9n
  text: |-
    ### Discoveries during the port

    - `MCPTool` holds one `MCPCatalogEntry` and one `MCPServer`. `name`, `description`, `parameters` and `outputSchema` all read off the entry, so the type carries no second copy of the metadata. `title` and the raw `inputSchema` stand on `tool.entry`, not on the tool.
    - The `Tool` conformance needs no `Generable` type: `Arguments = GeneratedContent`, as in the sibling. `parameters` is a computed property over the entry, which the protocol accepts.
    - `rendering(withBudget:)` stays as the one per-tool override. A private designated initializer takes the budget, and the public `init(entry:server:)` and the copy method both go through it.
    - `ToolContext.current` is never read by the verb itself: `MCPServer.call(name:arguments:)` captures it. With no context bound, a progress notification of the server routes nothing (`handleProgressNotification` requires `entry.context`), and the call returns the rendered result. The portability test proves it against the progress-reporting scripted tool.
    - A tool that a test registers after the connect is not in `discoveredTools`. The portability case builds its entry from an `MCP.Tool` of the same name and schema; the call reaches the server by name.
    - The nested integration package declares no `MCP` product, so its bare-session case cannot name `InMemoryTransport`. `ScriptedServer.startOnInMemoryPair()` (new, in the `MCPTestServer` product) starts the server on a fresh pair and returns the client end as `any Transport`. `MCPTestSupport.clientTransport(serving:over:)` now calls the same helper for `.inMemory`, so the pair is built in one place.
    - Shared helper: `MCPTestSupport.connectedMCPServer(serving:name:callTimeout:renderBudget:)` builds the scripted server, registers the tools and connects. `MCPServerCallTests.connected` and `MCPToolTests.connected` both call it. The `to:over:` overload gained a `renderBudget` parameter for the budget cases.
    - `ScriptedServer.progressToolCompletionText` became `public`, so a test can assert the rendered result of the progress tool.
    - The stale "which comes in a later task" sentences about `MCPTool` in the headers of `GeneratedContentCodec`, `ToolContentRenderer`, `SchemaConverter`, `MCPToolCatalog`, `MCPServer` and `MCPServer+Discovery` are updated.
    - `swift build --package-path IntegrationTests --build-tests` compiles the gated `MCPBareSessionTests`; it was not run, as the card states.
  timestamp: 2026-08-27T19:59:48.338556+00:00
- actor: claude-code
  id: 01m12cxdha6a06jx7djm4qtz3x
  text: |-
    ### implement — changed
    - evidence: 13 files. New: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPTool.swift`, `Tests/FoundationModelsMultitoolTests/MCPToolTests.swift`, `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/MCPBareSessionTests.swift`. Changed: `Tests/Support/MCPTestServer/ScriptedServer.swift` (`startOnInMemoryPair()`, public `progressToolCompletionText`), `Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift` (shared `connectedMCPServer(serving:...)`, `renderBudget` parameter), `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift` (uses the shared helper), and the headers of `GeneratedContentCodec.swift`, `ToolContentRenderer.swift`, `SchemaConverter.swift`, `MCPToolCatalog.swift`, `MCPServer.swift`, `MCPServer+Discovery.swift`. `swift build --build-tests`: no compiler warnings in the changed files. `swift test --filter MCPToolTests`: 15 tests in 1 suite pass. `swift build --package-path IntegrationTests --build-tests`: build complete. All 10 checkboxes on the card are ticked.
    - next: `test` step, full `swift test`.
  timestamp: 2026-08-27T19:59:52.874721+00:00
- actor: claude-code
  id: 01m12d9xy36xa742chq5ea4et4
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (f97576b) — 0 findings, 12 files reviewed, 7 validators attempted, 0 failed; no prior findings on the card
    - next: none. The task is done.
  timestamp: 2026-08-27T20:06:42.883847+00:00
- actor: claude-code
  id: 01m12da02mzdg54dknwahrewpt
  text: |-
    ### finish iteration 1 — done
    - implement: changed (13 files — `MCPTool.swift`, `MCPToolTests.swift`, the gated `MCPBareSessionTests.swift`, the shared test support, and six header updates)
    - test: green (swift test — 1247 tests in 92 suites, 0 failed, 0 skipped; IntegrationTests package builds)
    - commit: f97576b
    - review: clean (0 findings; no prior findings)
  timestamp: 2026-08-27T20:06:45.076246+00:00
depends_on:
- 01M112A9AT308HGW19PK815DJV
- 01M112AJNVGJ40ABS0QWPKEGPV
- 01M112CTS4HSY5R312NW7VK7SV
position_column: done
position_ordinal: ff9880
title: Port MCPTool as a plain Tool verb over the codec and the renderer
---
## What
Port `MCPTool`, the one `FoundationModels.Tool` conformer that stands for one server tool. In this package it is a verb: `Tool.name` is the MCP tool name, and the capability (next task) supplies the noun. eventplan.md § "Registration of capabilities": "MCP obeys the same grammar. The server is the noun, and the tool is the verb (`tools.github.createIssue`)."

**`MCPTool` is a plain `Tool`, and it is portable.** It does not conform to `BackgroundTool`. A plain `Tool` needs only `LanguageModelSession`; `BackgroundTool` means nothing without Router's engine. The verb reads `ToolContext.current` for progress and elicitation when a context is bound, and it works with no context at all (a post through `nil` is a no-op). Thus one `MCPTool` serves three hosts with no change: a bare Foundation Models session, a Router `RoutedSession`, and a MultiTool snippet. The result of an MCP call is the value; it has no content-plane store, so a background envelope would give the model a 4 KB tail and nothing else (eventplan.md § "The run plane and the content plane are different surfaces"). That is why the verb is synchronous. A host that mounts a long MCP verb on the native path gives it a background `ToolMount` at the mount site; the verb itself does not declare one.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/FoundationModelsMCP/MCPTool.swift` (366 lines) and `MCPToolCalling.swift`.
- Target: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPTool.swift`.
- `init(entry: MCPCatalogEntry, server: MCPServer)`. The `parameters` schema comes from `SchemaConverter`. `call(arguments: GeneratedContent) -> String` decodes with `GeneratedContentCodec.arguments(from:)`, calls `server.call(name:arguments:)`, and renders with `ToolContentRenderer` at the server's `RenderBudget` or this tool's own override (`rendering(withBudget:)` stays).
- Drop `waiting(for:)`, `wait`, `operationRoute`, and the `MCPToolCalling` protocol. The server is the one seam.
- **Verb legality.** The rule is `ToolAPIRenderer.isLegalTSIdentifier` (`[A-Za-z_$][A-Za-z0-9_$]*`), and the renderer already throws `ToolAPIRendererError` for an illegal `Tool.name` inside `render(...)`, thus an MCP tool named `create-issue` already fails at `buildRegistry()` today. Decision: keep that throw as the loud failure. Do not add a `MultiToolBuilderError.Kind` case, and do not map or rewrite the name: `findAPIs` must show the name the model calls. Add one sentence to the `MCPTool` header that says where the rule lives.
- Keep the type internal, the way `Execute` and `Read` are.

## Acceptance Criteria
- [x] `MCPTool.name` equals the server tool name, and `MCPTool.description` equals the server description.
- [x] `MCPTool.parameters` is the converted schema, and the model's `GeneratedContent` round-trips to the same `[String: Value]` the server receives.
- [x] The rendered output is `ToolContentRenderer`'s text, bounded by the render budget.
- [x] `MCPTool` does not conform to `BackgroundTool`.
- [x] With no `ToolContext` bound, `call(arguments:)` returns the rendered result, and a server progress notification during the call is a no-op (no crash, no event).
- [x] A tool named `create-issue` fails at `buildRegistry()` with `ToolAPIRendererError`, not at dispatch.
- [x] `swift build` succeeds.

## Tests
- [x] Port `MCPToolTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Drop the `waiting(for:)` and `operationRoute` cases; list them in the header. Add the illegal-name case.
- [x] Add a portability case: call `MCPTool.call(arguments:)` directly with no bound `ToolContext` (the bare-session path), against `ScriptedServer` with a tool that sends progress, and assert the rendered result. Add a gated case in `IntegrationTests/` (which imports the `MCPTestServer` product) that mounts the same `MCPTool` on a bare `LanguageModelSession(model: .default, tools: [tool])` and asserts the model's answer carries the server's result.
- [x] `swift test --filter MCPToolTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the type to make them pass. #eventplan #phase-4