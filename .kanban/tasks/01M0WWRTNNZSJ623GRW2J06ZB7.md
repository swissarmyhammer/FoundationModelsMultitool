---
assignees:
- claude-code
depends_on:
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WWQR0QYAT02TQ1D4CMVJQH
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: 8c80
title: Port GrepEngine, and make the tools.files.grep verb
---
## What
Port `GrepEngine`, and rewrite the `GrepFiles` operation as the plain `Tool` conformer `Grep`.

- Sources: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/GrepEngine.swift` and `.../Operations/GrepFiles.swift`
- Targets: `Sources/FoundationModelsMultitool/Capabilities/Files/GrepEngine.swift` and `.../Grep.swift`

`GrepEngine` is a behavioral port. It walks through the ported `FileWalker`. `Grep.swift` follows the Shell verb pattern:
- `struct Grep: Tool` with `name = "grep"`, so the path renders as `tools.files.grep`.
- A `@Generable` arguments struct with a `@Guide` on each parameter. Keep the source parameters, `outputMode` and `type` included.
- A flat `@Generable` result with a `correction` field.
- An unknown `outputMode` or `type` value gives the `EnumParameter` corrective message, in-band. The `type` corrective keeps its richer sentence that names the rejected value.
- The verb holds its `FileContext` as a constructor dependency.
- The doc comment carries the full behavioral contract and one example snippet.

## Acceptance Criteria
- [ ] The match results, the output modes, and the caps agree with the source.
- [ ] A bad regex, a bad path, and an unknown enum value each give a corrective result in-band. None of them throws.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `GrepFilesTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesGrepTests.swift`, adapted to the `Tool` call shape.
- [ ] `swift test --filter FilesGrepTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan