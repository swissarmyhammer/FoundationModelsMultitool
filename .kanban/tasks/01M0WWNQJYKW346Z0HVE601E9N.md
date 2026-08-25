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
- actor: claude-code
  id: 01m0x00bfdcp15xd69h5m0fwtq
  text: |-
    ### review — findings
    - evidence: 1 finding — Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift:903 (code-hygiene/magic-numbers-swift). Scope: review sha HEAD~1..HEAD, backend local. Counts: findings 1, confirmed 3, refuted 0.
    - next: Correct the finding. Replace each magic number in the file with a named constant. Then run the review again.
  timestamp: 2026-08-25T17:38:05.421193+00:00
- actor: claude-code
  id: 01m0x07ddj748m7wx05nq7v7x9
  text: |-
    Finding fix, with the scan of the whole file:

    - The `magic-numbers-swift` rule is swiftlint `no_magic_numbers` with `allowed_numbers: [0, 1, -1, 100]`. A declaration that names its value (`static let`, stored property, enum raw value, default parameter) does not report.
    - A scan of each numeric literal in the file found three offenders, all on the reported line: `0x1F`, `0x7F`, `0x9F` in `containsInvalidControlCharacter(_:)`. Each other literal is safe: `4096`, `0o222`, `0o444` sit in named `static let` declarations with doc comments; the `0` and `1` comparisons are in the rule's allow-list.
    - Fix: three new named constants in the constants block — `highestC0ControlScalar` (0x1F), `deleteControlScalar` (0x7F), `highestC1ControlScalar` (0x9F) — each with a doc comment that states the value, in the file's style. The comparison now reads the constants. No behavior change; this is the refactor phase, and the ported tests hold it green.
  timestamp: 2026-08-25T17:41:56.786270+00:00
- actor: claude-code
  id: 01m0x07fy96ec7ztersfd2gzr1
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift. Replaced the magic numbers 0x1F, 0x7F, 0x9F with the named constants `highestC0ControlScalar`, `deleteControlScalar`, `highestC1ControlScalar`, each with a doc comment that states the value. All other literals in the file already sit in named constants or in the rule's allow-list (0, 1, -1, 100). `swift build` — Build complete. `swift test --filter PathGuardTests` — 35 tests, 1 suite, all pass. The one build warning is the pre-existing mlx-swift bundle notice. The finding's checklist item is now `- [x]`.
    - next: /review
  timestamp: 2026-08-25T17:41:59.369031+00:00
- actor: claude-code
  id: 01m0x097w91c7rsz1xz1es1a6w
  text: |-
    ### test — green
    - evidence: swift test — 643 tests, 52 suites, all passed, 0 failed, 0 skipped. Only warning found: the named pre-existing one (missing creator for mutated node: mlx-swift_Cmlx.bundle/Contents/MacOS). No new warnings.
    - next: no fix needed. No edit made to PathGuard.swift.
  timestamp: 2026-08-25T17:42:56.649081+00:00
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

## Review Findings (2026-08-25 12:30)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 18 not reviewed.

> 18 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 18 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift:903` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.