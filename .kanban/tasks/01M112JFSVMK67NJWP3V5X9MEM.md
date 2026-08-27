---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11tx0heg41dp0vh5zpvw7fy
  text: |-
    ### Discoveries during the port

    - The discovery half stands in two new files. `MCPServer+Discovery.swift` holds `discoverAllTools()`, `mcpTools()`, `tool(named:)`, `catalog`, `makeCatalogSnapshot(epoch:identity:)` and `emitCatalogSnapshot()`. `MCPServer+LiveCatalog.swift` holds `handleToolListChangedNotification()`, `coalesceAndRelist()`, `relistOnce()` and the coalesce window constant. The stored state — `discoveredTools`, `catalogEpoch`, `catalogUpdates`, `catalogContinuation`, `toolListChangedGeneration`, `isCoalescingToolListChanged`, `coalescingTask` — stands in `MCPServer.swift`, because an extension cannot hold a stored property. A `deinit` finishes the stream.
    - The source stored each discovered tool as an `MCPTool` and converted it to a descriptor for the catalog. `MCPTool` is not in this package, so each tool is stored as the `MCPCatalogEntry` the catalog carries, and `mcpTools()` and `tool(named:)` vend that entry. `foundationModelsTools()` of the source is not ported.
    - `MCPCatalogEntry` and `MCPToolCatalog` are internal, so the discovery surface — `mcpTools()`, `tool(named:)`, `catalog`, `catalogUpdates` — is internal too. A public method must not expose an internal type. The rebuild task, in this package, is the reader.
    - `applyConnect(via:generation:)` now runs `discoverAllTools()` between the handshake and `.ready`, and emits one snapshot on success and one on a failure after a prior success. A discovery failure faults the connect the same as a handshake failure.
    - `disconnect()` emits no snapshot, so a disconnect-then-connect produces exactly two snapshots — the shape the ported `reconnectEmitsSnapshotReflectingReturningServer` case asserts. `disconnect()` cancels a coalescing watcher still in its window; the watcher checks `Task.isCancelled` after its sleep and re-lists nothing. That check is what gives `coalescingTask` a reader, so the property is not assign-only.
    - Every test of the live suite polls through `TestPoll.holds`, the one poll of this test target, and not through a copy of the source's `CatalogSnapshotRecorder.wait(forCount:timeout:)`.
    - `MCPTestSupport.connectedMCPServer(to:over:name:)` gains a `clock:` parameter with a real-clock default, so the live suite passes a `ManualClock` for the coalesce window.
    - Two source cases are not ported, because each drives the call path: `midCallFaultEmitsFaultedThenReadySnapshots` and `modelCallOnVanishedToolShortCircuitsToNotAvailableResult`. `toolResolutionReturnsNilAfterScriptedRemoval` is ported without its `toolNoLongerAvailableResult(named:)` assertions, which belong to the call path. One new case, `reconnectThroughRetainedFactoryEmitsOneSnapshot`, proves `reconnect()` emits exactly one snapshot. One new case, `dynamicToolsetScenarioEmitsOneSnapshotPerStage`, drives `startDynamicToolsetScenario()` and reads one snapshot per stage; it runs for the three stage delays of the scenario in real time.
    - `LiveCatalogTests` passed on four consecutive runs.
  timestamp: 2026-08-27T14:45:05.198309+00:00
- actor: claude-code
  id: 01m11tx7mp1htypq4y5rzrd7bs
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Discovery.swift, MCPServer+LiveCatalog.swift (new); MCPServer.swift, MCPServer+Connection.swift, MCPToolCatalog.swift (edited); Tests/FoundationModelsMultitoolTests/MCPServerDiscoveryTests.swift, LiveCatalogTests.swift (new); MCPToolCatalogTests.swift, Support/MCPTestSupport.swift (edited). `swift build --build-tests` clean; `swift test --filter 'MCPServerDiscoveryTests|LiveCatalogTests|Resilience'` — 28 tests in 3 suites pass; `LiveCatalogTests` green on four runs.
    - next: the `test` step runs the whole suite, then `commit`, then `review`.
  timestamp: 2026-08-27T14:45:12.470653+00:00
- actor: claude-code
  id: 01m11ty3ssekgh9y3w9zr8dsw5
  text: |-
    ### test — green
    - evidence: `swift test` — 1203 tests in 87 suites passed, 0 failed, 0 skipped; `swift build --build-tests` reports no compiler warning.
    - next: commit.
  timestamp: 2026-08-27T14:45:41.305275+00:00
depends_on:
- 01M112C9B7VKH4MEEVD832PG8R
position_column: doing
position_ordinal: '80'
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