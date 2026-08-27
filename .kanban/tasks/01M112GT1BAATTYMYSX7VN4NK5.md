---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12nm5bby6s5ng7sbzqksyf3
  text: |
    ### Research — picked up

    What the code already gives:

    - `RegistryStaging` (`Sources/FoundationModelsMultitool/RegistryHolder.swift`) and `Registry.makeSessionToolsAndStaging(librarian:sampleGenerator:)` vend the staging half. `MultiTool.turnWillBegin()` applies it. Both halves of the swap are done; only the watcher is missing.
    - `RegistrySource.rebuildRegistry()` is done (task `RegistryRebuildTests`). It reads each MCP catalog again and renders at the side.
    - `MCPServer.catalogUpdates` is an internal `AsyncStream<MCPToolCatalog>` with ONE consumer. A reconnect, a failed connect after a success, and a coalesced `tools/list_changed` re-list all emit through it. So no second path is needed for a reconnect.
    - `MCPServerPool` already states the hook: `attach(attachment: any Stoppable)`, and `shutdownAll()` stops the attachment before it closes the servers. Its header says the attachment is the surface refresher. So `SurfaceRefresher` conforms to `Stoppable`.
    - `MCPToolCatalogDiff` has no `isEmpty`. One is added.
    - `makeSessionTools(...)` is already synchronous and starts nothing. No change there.

    Design decisions:

    - The watch task must NOT hold the refresher strongly, or `deinit` could never run and the debug assertion could never fire. So the mutable rebuild state lives in a small private reference type the task holds, and the public class holds only the lifetime (the task and the join stream).
    - The last built catalog is kept per server name. A snapshot with no previous catalog always rebuilds: with no record, nothing can say the catalog did not move.
    - A snapshot is recorded as the new "last" only after the rebuild succeeded, so the next snapshot tries again after a failure.
    - `stop()` cancels the task, which ends each `for await` on `catalogUpdates`. An `AsyncStream` that a cancelled consumer leaves is finished, so a refresher that stopped never starts again. This is documented.

    The CLI wiring is task `^vsacz8f`, not this one.
  timestamp: 2026-08-27T22:32:06.763154+00:00
- actor: claude-code
  id: 01m12pc6wzcncw95f7em4evyrs
  text: |
    ### Implementation landed

    Test-first: the eight cases of `SurfaceRefresherTests.swift` were written against a stub that answered nothing, and the run showed 14 issues over 8 cases. Then the refresher was written, and the eight cases passed.

    What the code does:

    - `SurfaceRefresher` holds two halves. The public class holds the lifetime (the servers, the watch task, and the stream a late server joins on). A private `Rebuilding` class holds the rebuild state (the recorded registrations, and the last built catalog of each server). The watch task holds `Rebuilding` and never the refresher, so a refresher a host releases without a `stop()` IS deallocated while its task runs, and the `deinit` assertion fires. A task that held the refresher would keep it alive forever and the mistake would be silent.
    - `start()` runs one `Task` over a task group: one child for each server, plus the parent reading the join stream so `addServer(_:)` gives a late server a child of its own without a second watch task.
    - A snapshot with no last built catalog always rebuilds. With no record, nothing can say the catalog did not move.
    - The snapshot becomes the new last built catalog only after the rebuild succeeded. So a failure leaves the next snapshot measured against the same catalog, and the rebuild is tried again.
    - A cancelled rebuild logs nothing: a stop is the host ending the session, not a catalog the refresher cannot render. Without this guard, `stop()` would write a spurious failure line.

    Discoveries worth keeping:

    - **The connect snapshot always arrives.** An `AsyncStream` holds what it emitted before a consumer read it, so the snapshot of the connect reaches the refresher when it starts, after the registry was already built. The refresher rebuilds one time over a catalog that did not move. That is the cost of never missing a change that landed before the watch started, and it is documented in the file header. Each test case waits for that first stage and counts its own changes above it.
    - **`stop()` ends the watch for good.** A cancelled `for await` on an `AsyncStream` finishes that stream, so a refresher that stopped never starts again. A host that stopped a session makes a new refresher for the next one. Documented on the type.
    - `MCPToolCatalogDiff` had no `isEmpty`. One was added, documented as the refresher's one gate.

    Test support that moved, to keep no copy:

    - `Fixtures/LogReadbackFixtures.swift` (new) holds the one `OSLogStore` read of this test target. `ImaginedToolLogFixtures.swift` now reads through it instead of holding a second copy.
    - `Fixtures/HelpSurfaceFixtures.swift` (new) holds the one `return help();` run and decode. `RegistrySwapTests.swift` now reads through it instead of holding its own.

    The CLI wiring stays with task `^vsacz8f`. `SurfaceRefresher` conforms to `Stoppable`, so `MCPServerPool.attach(attachment:)` takes it and `shutdownAll()` stops it before it closes any server.
  timestamp: 2026-08-27T22:45:14.783016+00:00
- actor: claude-code
  id: 01m12pcdjcsjj2jw3wk8gpctvz
  text: |
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/MCP/SurfaceRefresher.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/MCPToolCatalog.swift, Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift (new), Tests/FoundationModelsMultitoolTests/Fixtures/LogReadbackFixtures.swift (new), Tests/FoundationModelsMultitoolTests/Fixtures/HelpSurfaceFixtures.swift (new), Tests/FoundationModelsMultitoolTests/Fixtures/ImaginedToolLogFixtures.swift, Tests/FoundationModelsMultitoolTests/RegistrySwapTests.swift. `swift build --build-tests` clean; `swift test` 1290 tests in 98 suites passed, 0 failures, 0 warnings; `swift test --filter SurfaceRefresherTests` 8 of 8 passed.
    - next: /review
  timestamp: 2026-08-27T22:45:21.612781+00:00
- actor: claude-code
  id: 01m12pctrxcf8kwah69k2tgcqm
  text: |
    Correction to the step record above: the file count is 7, not 6. The list itself is complete and correct — three new source and test files, one edited source file, two new test fixtures, and two edited test files, which is seven paths in all (`git status` agrees).
  timestamp: 2026-08-27T22:45:35.133391+00:00
depends_on:
- 01M112F1XGAN9VWW702AZPXVZ4
- 01M112FH3741JEQ7QN97C5E13R
position_column: doing
position_ordinal: '80'
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
- [x] `DynamicToolsetScenario` adds a tool → the server sends `tools/list_changed` → after the next turn tick, `help()` and a snippet see the new verb, with no host action.
- [x] A removed tool is gone from the surface after the tick, and a snippet that calls it gets the usual unknown-tool repairable error.
- [x] A burst of three changes before one tick gives one swap.
- [x] A rebuild failure (illegal verb in the new catalog) keeps the old surface and logs one line.
- [x] `stop()` ends the task; a registry built in a unit test with no refresher leaves no running task behind.
- [x] `swift build` succeeds.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift` with the criteria above. Drive the turn tick with a direct `turnWillBegin()` call. Assert `stop()` with a task-completion probe.
- [x] `swift test --filter SurfaceRefresherTests` passes.
- [x] Full `swift test` passes.

## Workflow
- Use `/tdd` — write the refresher tests first, then implement. #eventplan #phase-4