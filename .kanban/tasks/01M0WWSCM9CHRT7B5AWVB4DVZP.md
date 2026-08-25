---
assignees:
- claude-code
depends_on:
- 01M0WWRKSCECWP5XSEZBHGTF8T
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8e80'
title: Make the tools.files.patch verb from PatchFiles
---
## What
Rewrite the `PatchFiles` operation as the plain `Tool` conformer `Patch`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Operations/PatchFiles.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Patch.swift`

Shape:
- `struct Patch: Tool` with `name = "patch"`, so the path renders as `tools.files.patch`.
- A `@Generable` arguments struct with a `@Guide` on each parameter.
- A flat `@Generable` result with a `correction` field.
- Carry the `changeKinds` table from `PatchFiles` into `Patch.swift`. The later `FileChangeSetTests` port reads it.
- A patch that cannot parse, and a hunk that cannot apply, each give a corrective result in-band with the engine's description.
- A patch records into `FileContext.changes` when the journal records. A patch on a read-only context gives a corrective result in-band.
- The verb holds its `FileContext` as a constructor dependency.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] An applied patch gives the same tree state as the source operation.
- [ ] `Patch.swift` carries the `changeKinds` table.
- [ ] A patch that cannot parse, a hunk that cannot apply, a path outside the root, and a read-only context each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `PatchFilesTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesPatchTests.swift`, adapted to the `Tool` call shape.
- [ ] `swift test --filter FilesPatchTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass.