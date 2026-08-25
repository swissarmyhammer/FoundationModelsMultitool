---
assignees:
- claude-code
depends_on:
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WWNWDG0SPX34065AZ7JW8H
- 01M0WWQYXE8CCDSKQRPD3PX093
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: 8a80
title: Make the tools.files.write verb from WriteFile, without diagnostics
---
## What
Rewrite the `WriteFile` operation as the plain `Tool` conformer `Write`, in the pattern of `Capabilities/Shell/GetLines.swift`. Remove the diagnostics fold during the rewrite.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Operations/WriteFile.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Write.swift`

Shape:
- `struct Write: Tool` with `name = "write"`, so the path renders as `tools.files.write`.
- A `@Generable` arguments struct with a `@Guide` on each parameter.
- A flat `@Generable` result with a `correction` field.
- Remove the `diagnostics: FileDiagnostics?` field from the output and every fold of the bridge. Decision 2026-08-11 in eventplan.md.
- The write goes through `AtomicWriter`. The write records into `FileContext.changes` when the journal records.
- A write on a read-only context gives a corrective result in-band.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] A write is atomic and lands under the root only.
- [ ] The output carries no diagnostics field.
- [ ] A path outside the root and a read-only context each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `WriteFileTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesWriteTests.swift`, adapted to the `Tool` call shape. Remove the diagnostics cases.
- [ ] `swift test --filter FilesWriteTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan