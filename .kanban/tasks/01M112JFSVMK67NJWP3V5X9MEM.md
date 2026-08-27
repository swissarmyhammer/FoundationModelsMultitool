---
assignees:
- claude-code
depends_on:
- 01M112C9B7VKH4MEEVD832PG8R
position_column: todo
position_ordinal: '9280'
title: Port MCPServer discovery and the live catalog stream
---
## What
Port the discovery half of `MCPServer`: paginated `tools/list`, `mcpTools()`, `tool(named:)`, and the coalesced `tools/list_changed` re-list with its `catalogUpdates` stream. eventplan.md § "Consolidation of the siblings": "an MCP `tools/list_changed` starts a full rebuild." This stream is what the rebuild task consumes.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`: the discovery round trip after connect, `mcpTools()` (line ~3356), `tool(named:)` (line ~3393), and the section `// MARK: - Live catalog: coalesced tools/list_changed re-list` (lines 3592–3672: `handleToolListChangedNotification()`, `coalesceAndRelist()`, `relistOnce()`), plus the declarations that section uses from elsewhere in the actor: `catalogEpoch` (line ~661), `catalogUpdates` / `catalogContinuation` (lines ~685–689), and `toolListChangedCoalesceWindow` (line ~986). The reconnect emit is at line ~3183.
- Target: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Discovery.swift` and `MCPServer+LiveCatalog.swift`.
- The snapshot type is `MCPToolCatalog` from the catalog task. Each snapshot carries the epoch and the state.
- A reconnect that reaches `.ready` again emits a snapshot on `catalogUpdates` also (the source does this at line ~3183; keep it), so a consumer sees a reconnect the same way it sees a `list_changed`. Say so in the doc comment of `catalogUpdates`.
- `catalogUpdates` is one `AsyncStream` with one continuation; a second reader is a programming error, the same as the source states. Keep that note.

## Acceptance Criteria
- [ ] After connect, `mcpTools()` returns each tool of a multi-page `tools/list`.
- [ ] A burst of `tools/list_changed` notifications gives exactly one new catalog snapshot after the coalesce window, with the epoch incremented by one.
- [ ] A reconnect emits one snapshot.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `MCPServerDiscoveryTests.swift` and the live cases of `LiveCatalogTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`, over the `DynamicToolsetScenario` extension of `ScriptedServer`. Add the reconnect-snapshot case.
- [ ] `swift test --filter MCPServerDiscoveryTests` passes.
- [ ] `swift test --filter LiveCatalogTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #eventplan #phase-4