---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0wyztycwzj66ttghgk9sp59
  text: |-
    Research done. Discoveries:

    - The source `PathCorrective.swift` refers to the `CorrectiveFailure` protocol, which lives in the sibling file `CorrectiveResult.swift`. That file is not in this task's scope, and no type in this package declares it. The tests only read `failure.correctiveMessage`. Thus the ported `UnreadableFile` conforms to `Error` directly and keeps `correctiveMessage` as a plain property. A later verb port can add the protocol.
    - The two `FileContext` test cases sit at the end of the source `PathGuardTests.swift` (`fileContextExposesRootGuardAndReadOnlyFlag`, `fileContextDefaultsToReadWrite`). They stay out, as the card states. The suite doc comment loses its `FileContext` mention.
    - `TestSupport.makeTemporaryDirectory(named:)` is already in the test target (task ^y2th7j4) and carries a `periphery:ignore` note that names these ported suites.
    - The Shell capability keeps its internal types with no explicit access modifier, and tests reach them through `@testable import`. The port drops the source's `public` to match.
    - Header comments follow the `//` block style of `ShellCapability.swift` and `GetLines.swift`, and cite eventplan.md § "Consolidation of the siblings" for the in-band corrective contract.
  timestamp: 2026-08-25T17:20:19.916930+00:00
- actor: claude-code
  id: 01m0wzadjj5fjt4gyngnfjg1rj
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift, Sources/FoundationModelsMultitool/Capabilities/Files/PathCorrective.swift, Tests/FoundationModelsMultitoolTests/PathGuardTests.swift, Tests/FoundationModelsMultitoolTests/PathCorrectiveTests.swift. TDD order held: the ported tests failed to compile first (missing `PathGuard`/`PathCorrective`), then the code ports made them pass. `swift build` — Build complete. `swift test --filter PathGuardTests` — 35 tests, all pass. `swift test --filter PathCorrectiveTests` — 5 tests, all pass. Zero compiler warnings in the ported files; the one build warning is the pre-existing mlx-swift bundle notice, present before this change. The two `FileContext` cases stayed out, per the card. The ported types stay internal, per the Shell-capability pattern; the sibling's `CorrectiveFailure` protocol is out of scope, thus `UnreadableFile` conforms to `Error` directly.
    - next: /review
  timestamp: 2026-08-25T17:26:06.674410+00:00
- actor: claude-code
  id: 01m0wzfqbzc3ftp7ttk0zdcdy7
  text: |-
    ### test — green
    - evidence: `swift test` — 643 tests, 52 suites, all passed; 0 failed; 0 skipped. `swift build --build-tests` clean.
    - note: one warning is present. It is not new. It is present with and without the working-tree change. Text: "warning: missing creator for mutated node: ('.../.build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS')". It comes from the mlx-swift dependency build plan, not from project code.
    - next: none. The build is clean.
  timestamp: 2026-08-25T17:29:00.543473+00:00
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
title: Port PathGuard and PathCorrective into Capabilities/Files
---
## What
Port `PathGuard` and `PathCorrective` from the FileTool package into this package. This is a behavioral port: keep the logic the same, and write new header comments in the style of `Capabilities/Shell` (see `ShellCapability.swift` and `GetLines.swift`).

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/PathGuard.swift` and `.../PathCorrective.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift` and `.../PathCorrective.swift`

Refer to eventplan.md § "Consolidation of the siblings": the Files capability gets "`PathGuard` root bounds", and corrective results (a path outside the root) stay in-band, never thrown.

Note on the tests: `PathGuardTests.swift` lines 510 and 518 construct a `FileContext`, which this task does not have yet. Move those two cases to the FileContext task. Do not port them here.

## Acceptance Criteria
- [x] `PathGuard` bounds each path to the root and to the additional roots, with the same rules as the source (symlink policy included).
- [x] A path outside the root gives a corrective message in-band. It does not throw.
- [x] `swift build` succeeds.

## Tests
- [x] Port `PathGuardTests.swift` (without the two `FileContext` cases at source lines 510 and 518) and `PathCorrectiveTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [x] `swift test --filter PathGuardTests` passes.
- [x] `swift test --filter PathCorrectiveTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan