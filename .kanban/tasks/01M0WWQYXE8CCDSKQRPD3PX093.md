---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0xd309hky79yn1n9pcjmfw7
  text: |-
    Research done. Discoveries:
    - The pattern to copy is `Capabilities/Files/Glob.swift`: a plain `Tool` with `name`, `description`, `context`, `init(context:)`, and `call(arguments:)` in an extension. The arguments and the result are `@Generable`.
    - The helpers are in place: `Hashline` (tag, splitLines, wholeFileHash), `EnumParameter.unknownValueMessage`, `PathCorrective.readData` / `pathErrorMessage`, `PathGuard.validate(_:for:)`, and `Result.resolve(corrective:then:)` from `CorrectiveResult.swift`.
    - The corrective on a bad path, a missing file, a binary file, an out-of-range bound, and an unknown `format` stays in band as the `correction` field of the flat result. Nothing throws.
    - One incorrect comment found: `Hashline.taggedLines(of:)` says this card (^d3px093) makes the read verb render it. In the source repository, `WriteFile` and `EditFile` are the callers, not `ReadFile`. The read verb windows through `Hashline.tag(lines:startingAtLine:)`. This card corrects that comment to name the write card (^p238zzp) and the edit card (^v5xap97).
    - The card's acceptance criteria add one test the source suite does not have: a path outside the root gives a correction. The port adds that test in the pattern of `FilesGlobTests.pathOutsideTheSessionRootIsCorrective`.
  timestamp: 2026-08-25T21:26:43.761454+00:00
- actor: claude-code
  id: 01m0xdbwpkkxr2p6zcx40azdmg
  text: |
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift (new verb), Tests/FoundationModelsMultitoolTests/FilesReadTests.swift (new suite, 21 tests), Sources/FoundationModelsMultitool/Capabilities/Files/Hashline.swift (corrected the stale `taggedLines(of:)` comment to name the write card ^p238zzp and the edit card ^v5xap97 as the future callers). TDD: the suite failed first (cannot find 'Read' in scope), then passed. `swift test --filter FilesReadTests` — 21 tests pass. Full `swift test` — 865 tests in 65 suites pass. `swift build` — complete, no warning from source code.
    - next: /review
  timestamp: 2026-08-25T21:31:34.995919+00:00
- actor: claude-code
  id: 01m0xdfand2rq8n28sp475112p
  text: |-
    ### test — green
    - evidence: swift test — 865 tests passed, 65 suites, 0 failed, 0 skipped. swift build --build-tests clean of new warnings; only the known pre-existing mlx-swift "missing creator for mutated node" notice is present.
    - next: none
  timestamp: 2026-08-25T21:33:27.597187+00:00
depends_on:
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
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
- [x] Each read format of the source renders byte for byte the same, the hashline format included.
- [x] A path outside the root, a missing file, and an unknown `format` each give a corrective result in-band. None of them throws.
- [x] `swift build` succeeds.

## Tests
- [x] Port `ReadFileTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/FilesReadTests.swift`, adapted to the `Tool` call shape.
- [x] `swift test --filter FilesReadTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan