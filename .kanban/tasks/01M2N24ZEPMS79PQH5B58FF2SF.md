---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2nem0ktb6n5gba07prbcffg
  text: |-
    Picked up. Research done.

    Discoveries:
    - `OperationDescribing` refines `Tool` (FoundationModelsExtras/OperationEvents/OperationDescribing.swift), so `tool as? any OperationDescribing` works on an `any Tool`, and a verb can go into `PendingTool.grouped` with no new case.
    - `RegistrySource.expanded()` is the one place that makes the queue. The render loop of `buildRegistry()` calls `ToolAPIRenderer.render(tool)` in two places; a shared helper will pick `OperationVerbTool.render()` for a verb.
    - `CatalogEntryTool(name:description:)` (Fixtures/MultiToolExecutionFixtures.swift) is a plain tool with a settable name, so the `notes` standalone collision needs no new plain fixture.
    - No fixture gives an operation tool the name `bad-name`. A wrapper fixture around `NotesOperationTool` with a settable name will go into `Fixtures/OperationToolFixtures.swift`.
    - `BuilderSurfaceTests.golden(named:)` is `private static`. The same 5 lines are also in `ToolAPIRendererTests`. The new suite will read the golden the same way, through `#filePath` beside the suite.
    - `Package.swift` already copies `Goldens`, so the new golden file needs no manifest change.
  timestamp: 2026-09-16T15:50:57.914825+00:00
- actor: claude-code
  id: 01m2nexr0rzj7vp0dnrfhzsag9
  text: |-
    Implementation landed, with /tdd.

    RED: `OperationMountTests` (8 tests) failed with 10 issues before the change. The registry mounted the fused `notes` entry, no verb path was present, and the golden file did not exist.

    GREEN: `RegistrySource.swift` now expands each `OperationDescribing` tool in `expanded()`, which is `throws`:
    - `standalonePendingTools(for:)` gives `.grouped(group: tool.name, tool: verb)` for each verb of a standalone operation tool, and `.standalone(tool)` for a plain tool.
    - `groupedPendingTools(for:under:)` flattens the verbs into the group. The capability case calls it under the noun, inside the claim positions.
    - `verbs(of:)` makes one `OperationVerbTool` for each `operationDescriptors` element, in descriptor order.
    - `descriptor(of:)` renders an `OperationVerbTool` through its own `render()`, and every other tool through `ToolAPIRenderer.render(_:)`. Both render branches call it.
    - The doc comments of `buildRegistry()`, `rebuildRegistry()` and `expanded()` name the `OperationVerbTool.init` error and say it propagates unchanged.

    Golden: `Goldens/OperationSurface.ts.txt` was written from the real `surface.source` of `Builder().addTool(NotesOperationTool()).buildRegistry()` (the test wrote it to the scratchpad for one run, then the copy went into `Goldens/`; SHA-256 of both files is equal). The test reads it back through `RepositoryFile.read(relativePath:)` and trims newlines, as `BuilderSurfaceTests.golden(named:)` does.

    Fixture: `RenamedNotesOperationTool` in `Fixtures/OperationToolFixtures.swift` wraps `NotesOperationTool` under a name the test gives, for the `bad-name` case. `CatalogEntryTool(name: "notes", ...)` is the plain tool of the collision case.

    What did not work: `GeneratedContent` has no `elements()`; the test reads an array through `content.kind` and `case .array`.

    Not done on purpose: no change to `MultiToolBuilder.swift`, `Package.swift` or `Package.resolved`, as the card asks. No commit.
  timestamp: 2026-09-16T15:56:16.792434+00:00
- actor: claude-code
  id: 01m2ney29ms1kj5ryq9sjtfbqx
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Surface/RegistrySource.swift (modified), Tests/FoundationModelsMultitoolTests/OperationMountTests.swift (new), Tests/FoundationModelsMultitoolTests/Goldens/OperationSurface.ts.txt (new), Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift (modified). `swift test --filter OperationMountTests`: 8 tests, 8 passed. `swift test --filter BuilderSurfaceTests`: 11 tests, 11 passed, no change. `swift test`: 1485 tests in 118 suites passed, 0 failures.
    - next: /review
  timestamp: 2026-09-16T15:56:27.316571+00:00
depends_on:
- 01M2N245TZ7KAS9VJNEM3VDM0J
position_column: doing
position_ordinal: '80'
title: Expand an OperationDescribing tool into its verbs in RegistrySource.buildRegistry
---
## What

Make the registry mount an operation tool as one group of verbs. Change `Sources/FoundationModelsMultitool/Surface/RegistrySource.swift` only; the builder API in `Surface/MultiToolBuilder.swift` does not change, so `addTool`, `addGroup(named:_:)`, `register(noun:tool:)` and `withCapability` all accept an operation tool with no new method.

In `expanded()`, when a queued tool casts to `any OperationDescribing`, replace it with one `OperationVerbTool` per `operationDescriptors` element, in descriptor order:

- `.standalone(tool)` becomes `.grouped(group: tool.name, tool: verb)` for each verb. The tool name becomes the group, so `notes` gives `tools.notes.addNote`. The existing `.illegalGroupName` check then rejects a tool name that is not a legal identifier, and the existing standalone-name against group-name check rejects a standalone tool named `notes` beside it.
- `.grouped(group:, tool:)` becomes `.grouped(group:, tool: verb)` for each verb. The verbs flatten into that group. A verb name that collides with another tool or verb in the group fails with the existing `.duplicateName` error.
- A tool inside a `Capability` follows the grouped rule under the capability noun. The `CapabilityClaim.toolPositions` range must cover every verb the expansion added, so the noun-ownership check still passes for the capability's own verbs.

`OperationVerbTool.init` throws, so `expanded()` becomes `throws`. `buildRegistry()` propagates that error unchanged, the same posture its doc comment states for `ToolAPIRendererError`, and `rebuildRegistry()` inherits it through `refreshed().buildRegistry()`. Update the doc comments of both to say so.

In `buildRegistry()`, render an `OperationVerbTool` with its own `render()`, not with the generic `ToolAPIRenderer.render(tool)`. The `toolsByPath` entry for each verb path is the verb tool itself, so `MultiTool.makeLiveTools` and `makePreamble` need no change, and `Entry.journalOp` gives `"\(verb) \(group)"` as it does for every grouped tool.

Do not mount the fused form. There is no `tools.notes({op})` entry beside the verbs.

Add the golden `Tests/FoundationModelsMultitoolTests/Goldens/OperationSurface.ts.txt` with the full rendered surface for the five-verb fixture.

## Acceptance Criteria

- [x] `MultiTool.Builder().addTool(fixture).buildRegistry()` gives entries with paths `notes.addNote`, `notes.getNote`, `notes.listNote`, `notes.deleteNote`, `notes.tagNote`, in that order, and no entry with path `notes`.
- [x] The rendered `surface.source` equals `Goldens/OperationSurface.ts.txt` byte for byte, in the format of `Goldens/BuilderSurface.ts.txt`.
- [x] `addGroup(named: "code", [fixture])` gives paths `code.addNote` and the rest, with no `code.notes` level.
- [x] A `Capability` whose `tools` hold the fixture mounts the verbs under the capability noun, and the noun-ownership check passes.
- [x] Two operation tools in one group with one shared op string fail with `MultiToolBuilderError.kind == .duplicateName` and the verb name in the message.
- [x] A standalone operation tool whose name is `bad-name` fails with `.illegalGroupName`.
- [x] A standalone plain tool named `notes` beside the operation tool `notes` fails with `.duplicateName`.
- [x] After `rebuildRegistry()`, the verb paths are the same, and a note added through `notes.addNote` on the first registry is returned by `notes.listNote` on the rebuilt registry. This pins the shared parent store; the parent is a value type, so instance identity is not the check.

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/OperationMountTests.swift`: the eight criteria above, over the fixture in `Fixtures/OperationToolFixtures.swift`. Read the golden the way `BuilderSurfaceTests.golden(named:)` does.
- [x] Add `OperationSurface.ts.txt` under the `Goldens` resource directory that `Package.swift` already copies.
- [x] Run `swift test --filter OperationMountTests`; expect all pass. Run `swift test --filter BuilderSurfaceTests`; expect no change.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools