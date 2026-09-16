---
assignees:
- claude-code
depends_on:
- 01M2N245TZ7KAS9VJNEM3VDM0J
position_column: todo
position_ordinal: '8380'
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

- [ ] `MultiTool.Builder().addTool(fixture).buildRegistry()` gives entries with paths `notes.addNote`, `notes.getNote`, `notes.listNote`, `notes.deleteNote`, `notes.tagNote`, in that order, and no entry with path `notes`.
- [ ] The rendered `surface.source` equals `Goldens/OperationSurface.ts.txt` byte for byte, in the format of `Goldens/BuilderSurface.ts.txt`.
- [ ] `addGroup(named: "code", [fixture])` gives paths `code.addNote` and the rest, with no `code.notes` level.
- [ ] A `Capability` whose `tools` hold the fixture mounts the verbs under the capability noun, and the noun-ownership check passes.
- [ ] Two operation tools in one group with one shared op string fail with `MultiToolBuilderError.kind == .duplicateName` and the verb name in the message.
- [ ] A standalone operation tool whose name is `bad-name` fails with `.illegalGroupName`.
- [ ] A standalone plain tool named `notes` beside the operation tool `notes` fails with `.duplicateName`.
- [ ] After `rebuildRegistry()`, the verb paths are the same, and a note added through `notes.addNote` on the first registry is returned by `notes.listNote` on the rebuilt registry. This pins the shared parent store; the parent is a value type, so instance identity is not the check.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/OperationMountTests.swift`: the eight criteria above, over the fixture in `Fixtures/OperationToolFixtures.swift`. Read the golden the way `BuilderSurfaceTests.golden(named:)` does.
- [ ] Add `OperationSurface.ts.txt` under the `Goldens` resource directory that `Package.swift` already copies.
- [ ] Run `swift test --filter OperationMountTests`; expect all pass. Run `swift test --filter BuilderSurfaceTests`; expect no change.

## Workflow
- Use `/tdd`: write the failing tests first, then implement to make them pass. #operation-tools