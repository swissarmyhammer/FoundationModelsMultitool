---
assignees:
- claude-code
depends_on:
- 01M112A9AT308HGW19PK815DJV
- 01M112AJNVGJ40ABS0QWPKEGPV
- 01M112CTS4HSY5R312NW7VK7SV
position_column: todo
position_ordinal: '8980'
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
- [ ] `MCPTool.name` equals the server tool name, and `MCPTool.description` equals the server description.
- [ ] `MCPTool.parameters` is the converted schema, and the model's `GeneratedContent` round-trips to the same `[String: Value]` the server receives.
- [ ] The rendered output is `ToolContentRenderer`'s text, bounded by the render budget.
- [ ] `MCPTool` does not conform to `BackgroundTool`.
- [ ] With no `ToolContext` bound, `call(arguments:)` returns the rendered result, and a server progress notification during the call is a no-op (no crash, no event).
- [ ] A tool named `create-issue` fails at `buildRegistry()` with `ToolAPIRendererError`, not at dispatch.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `MCPToolTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Drop the `waiting(for:)` and `operationRoute` cases; list them in the header. Add the illegal-name case.
- [ ] Add a portability case: call `MCPTool.call(arguments:)` directly with no bound `ToolContext` (the bare-session path), against `ScriptedServer` with a tool that sends progress, and assert the rendered result. Add a gated case in `IntegrationTests/` (which imports the `MCPTestServer` product) that mounts the same `MCPTool` on a bare `LanguageModelSession(model: .default, tools: [tool])` and asserts the model's answer carries the server's result.
- [ ] `swift test --filter MCPToolTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the type to make them pass. #eventplan #phase-4