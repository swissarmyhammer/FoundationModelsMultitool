---
assignees:
- claude-code
depends_on:
- 01M0WWQAT9YQ2XN087287TZKDP
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WWQYXE8CCDSKQRPD3PX093
- 01M0WWR5S34QZDKV15KP238ZZP
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: 8d80
title: Make the tools.files.edit verb from EditFile, without diagnostics
---
## What
Rewrite the `EditFile` operation as the plain `Tool` conformer `Edit`. Remove the diagnostics fold during the rewrite.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Operations/EditFile.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Edit.swift`

Shape:
- `struct Edit: Tool` with `name = "edit"`, so the path renders as `tools.files.edit`. eventplan.md § "Registration of capabilities: noun/verb" names this exact file: "`Capabilities/Files/Edit.swift` holds the `@Generable` Arguments, the Output, the handler that reads `ToolContext.current`, the doc comment, and one example snippet."
- A `@Generable` arguments struct with a `@Guide` on each parameter. The edit payload goes to the shape-inferred dispatch of the ported `EditEngine`, hashline anchors included.
- A flat `@Generable` result with a `correction` field.
- Remove the `diagnostics` field from the output and every fold of the bridge. Decision 2026-08-11 in eventplan.md.
- An edit records into `FileContext.changes` when the journal records. An edit on a read-only context gives a corrective result in-band.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] Each edit strategy of the source gives the same file content, hashline-anchored edits included.
- [ ] The output carries no diagnostics field.
- [ ] A payload that cannot resolve, a path outside the root, and a read-only context each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `EditFileTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesEditTests.swift`, adapted to the `Tool` call shape. Remove the diagnostics cases.
- [ ] `swift test --filter FilesEditTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan