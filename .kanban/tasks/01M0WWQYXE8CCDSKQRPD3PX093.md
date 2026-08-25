---
assignees:
- claude-code
depends_on:
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8980'
title: Make the tools.files.read verb from ReadFile
---
## What
Rewrite the `ReadFile` operation as the plain `Tool` conformer `Read`, in the pattern of `Capabilities/Shell/GetLines.swift`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/Operations/ReadFile.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift`

Shape:
- `struct Read: Tool` with `name = "read"`, so the path renders as `tools.files.read`.
- A `@Generable` arguments struct with a `@Guide` on each parameter. Keep the source parameters, the `format` enum values included. `@OperationParam` aliases do not port; keep the canonical names.
- A flat `@Generable` result with a `correction` field: content and correction are exclusive.
- The verb holds its `FileContext` as a constructor dependency.
- An unknown `format` value gives the `EnumParameter` corrective message, in-band.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] Each read format of the source renders byte for byte the same, the hashline format included.
- [ ] A path outside the root, a missing file, and an unknown `format` each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `ReadFileTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesReadTests.swift`, adapted to the `Tool` call shape.
- [ ] `swift test --filter FilesReadTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan