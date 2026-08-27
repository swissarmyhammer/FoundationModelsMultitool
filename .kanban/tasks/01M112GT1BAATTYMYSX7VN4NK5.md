---
assignees:
- claude-code
depends_on:
- 01M112F1XGAN9VWW702AZPXVZ4
- 01M112FH3741JEQ7QN97C5E13R
position_column: todo
position_ordinal: '9080'
title: Wire catalogUpdates and reconnects to rebuild-and-stage
---
## What
Join the two halves of rebuild-and-swap. eventplan.md § "Consolidation of the siblings": "A late server, a reconnect, or an MCP `tools/list_changed` starts a full rebuild."

- Add `Sources/FoundationModelsMultitool/Capabilities/MCP/SurfaceRefresher.swift`: `public final class SurfaceRefresher: Sendable` with an explicit owner and lifetime. `init(source: RegistrySource, staging: any RegistryStaging, servers: [MCPServer])`, `start()`, and `stop()`. `start()` runs one `Task` that reads each server's `catalogUpdates` stream (merged with a task group). On each snapshot whose `diff(from:)` against the last built catalog is not empty, it calls `source.rebuildRegistry()` and `staging.stage(_:)`. A rebuild that throws logs one line and keeps the old surface; the next snapshot tries again. `stop()` cancels the task and awaits it. `deinit` asserts the task is stopped in debug builds.
- **No task starts in a factory.** `Registry.makeSessionTools(...)` stays synchronous and starts nothing (unit tests call it freely; `MultiToolExecutionTests.swift` calls it three times in one suite). The host makes the refresher after the session tools, and calls `start()`; the session sweep calls `stop()`. `multitool-cli` is the reference host (its task updates for this).
- Coalesce: several snapshots between two turns give one rebuild of the newest, because `stage(_:)` keeps only the newest.
- A reconnect emits a snapshot through the same stream (the discovery task keeps that emit); no second path is necessary.
- A late server (connected after `build()`): `addServer(_:) async throws` on the refresher adds it to the source and rebuilds.

## Acceptance Criteria
- [ ] `DynamicToolsetScenario` adds a tool → the server sends `tools/list_changed` → after the next turn tick, `help()` and a snippet see the new verb, with no host action.
- [ ] A removed tool is gone from the surface after the tick, and a snippet that calls it gets the usual unknown-tool repairable error.
- [ ] A burst of three changes before one tick gives one swap.
- [ ] A rebuild failure (illegal verb in the new catalog) keeps the old surface and logs one line.
- [ ] `stop()` ends the task; a registry built in a unit test with no refresher leaves no running task behind.
- [ ] `swift build` succeeds.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift` with the criteria above. Drive the turn tick with a direct `turnWillBegin()` call. Assert `stop()` with a task-completion probe.
- [ ] `swift test --filter SurfaceRefresherTests` passes.
- [ ] Full `swift test` passes.

## Workflow
- Use `/tdd` — write the refresher tests first, then implement. #eventplan #phase-4