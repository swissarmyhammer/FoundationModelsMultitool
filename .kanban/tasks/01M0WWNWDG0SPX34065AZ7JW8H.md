---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0x4d9z599m6pgj5rcdeka0r
  text: |-
    Research and port notes:
    - The port follows the package convention: the type is `internal`, not `public`, the same as `Hashline`, `PathGuard`, and `PathCorrective` beside it. The file header records the provenance and the visibility change, in the `Hashline.swift` header style.
    - `Hashline.splitLines(_:)` and its `Line.terminator` field are already in place, thus `detectLineEnding(in:)` ported without change.
    - TDD order held: the test suite went in first and failed with "cannot find 'AtomicWriter' in scope" on each use, then the source made it pass. 21 tests.
    - Test additions beyond the sibling suite, thus each declaration has a caller and no `periphery:ignore` marker is necessary: `decodedText(at:)` gets three tests (UTF-8 file, missing file, undecodable bytes), and `StagedWrite.permissionBits` gets expectations in the fresh-target and executable-mode tests. The sibling's `DecodedText` explicit `init` was dropped — the memberwise initializer serves an internal struct.
    - Rule reconciliation against the full validator dump: one `magic-numbers-swift` hit was corrected during the work (`String(_, radix: 8)` in a test message passed the literal `8` as a call argument; the message no longer formats the mode). Mode and byte literals in the tests are named `static let` constants, which the rule keeps silent.
    - `periphery scan` (validator shape: `--skip-build --index-store-path .build/out --retain-public` plus the retain flags, test targets report-excluded, after `swift build --build-tests`) reports zero findings for `AtomicWriter.swift` and for `Capabilities/Files`. The only rows are the pre-existing `Unused parameter` reports in `JSCInterpreter.swift`, a kind the validator drops.
  timestamp: 2026-08-25T18:55:04.165394+00:00
- actor: claude-code
  id: 01m0x4det6vpcjqvhcwd9fr57g
  text: |-
    ### implement — changed
    - evidence: 2 new files — Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift, Tests/FoundationModelsMultitoolTests/AtomicWriterTests.swift. `swift test --filter AtomicWriterTests` — 21/21 pass. Full `swift test` — 707 tests in 56 suites, 0 failed, 0 skipped. `swift build` succeeds; the one build warning is the known pre-existing mlx-swift bundle warning. periphery (validator shape, --build-tests index) — 0 findings in the changed files. All five acceptance-criteria items verified against the code and checked.
    - next: /review
  timestamp: 2026-08-25T18:55:09.126292+00:00
- actor: claude-code
  id: 01m0x4fx15pmpvb8pqj1x1tvh1
  text: |-
    ### test — green
    - evidence: swift test — 707 passed, 0 failed, 0 skipped; 1 pre-existing warning seen: "missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')" (known, not chased); 0 new warnings.
    - next: none. The build is clean.
  timestamp: 2026-08-25T18:56:29.221537+00:00
- actor: claude-code
  id: 01m0x5ch0rrzy83m6cdxz09k1a
  text: |-
    ### review — findings
    - evidence: 1 finding — Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift:260 (code-hygiene/magic-numbers-swift). Scope: review sha ae82449~1..ae82449, backend local. Counts: findings 1, confirmed 3, refuted 0.
    - next: replace the magic number with a named constant, then run the review again.
  timestamp: 2026-08-25T19:12:07.192378+00:00
- actor: claude-code
  id: 01m0x5fdmafwxgh83tdznq810j
  text: |-
    Correction of the review finding (`code-hygiene/magic-numbers-swift`, AtomicWriter.swift:260):
    - The cause: the three hex byte literals `0xEF, 0xBB, 0xBF` sat inside the array literal of `utf8ByteOrderMark`. The rule (swiftlint `no_magic_numbers`) reports a literal in an array; it does not report a declaration that names its value.
    - The fix: each byte now has its own named constant — `utf8ByteOrderMarkFirstByte`, `utf8ByteOrderMarkSecondByte`, `utf8ByteOrderMarkThirdByte` — each with a doc comment that states its value. The `utf8ByteOrderMark` array is built from the three named constants.
    - Full-file sweep: the other numeric literals in the file are `0` and `1` (in the allowed set [0, 1, -1, 100]) or direct named bindings (`permissionBitMask: mode_t = 0o777`), which the rule keeps silent. No other cause remains in the file.
  timestamp: 2026-08-25T19:13:42.026697+00:00
- actor: claude-code
  id: 01m0x5fj256k103chb219v9yf2
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift (the three byte-order-mark byte literals became named constants with doc comments; the finding checklist item is now checked). `swift build` succeeds. `swift test --filter AtomicWriterTests` — 21/21 pass. The one build warning is the known pre-existing mlx-swift bundle warning.
    - next: /review
  timestamp: 2026-08-25T19:13:46.565702+00:00
- actor: claude-code
  id: 01m0x5hsgx383bx3ge0v2zvaqr
  text: |-
    ### test — green
    - evidence: `swift test` — 707 tests passed, 0 failed, 0 skipped, in 56 test suites.
    - warnings: only the known old warning from mlx-swift, "missing creator for mutated node". This warning is named here. No action is needed on it.
    - new warnings: none found.
    - next: none. The build is clean.
  timestamp: 2026-08-25T19:14:59.741870+00:00
- actor: claude-code
  id: 01m0x5s4pnpqnb0y4vmb1tcsag
  text: |-
    ### review — clean
    - evidence: `review sha f1a3018~1..f1a3018` (backend: local) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 1 file reviewed. The one prior finding item is checked.
    - next: none — the task moved to done.
  timestamp: 2026-08-25T19:19:00.565623+00:00
- actor: claude-code
  id: 01m0x5sm5w70n6kxqagecbrhfh
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — named the three UTF-8 BOM byte constants in AtomicWriter.swift
    - test: green — swift test, 707 tests in 56 suites, 0 failed
    - commit: f1a3018 (iteration 1: ae82449)
    - review: clean — review sha f1a3018~1..f1a3018, 0 findings, prior item checked
    - task landed in done
  timestamp: 2026-08-25T19:19:16.412807+00:00
depends_on:
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: done
position_ordinal: fa80
title: Port AtomicWriter into Capabilities/Files
---
## What
Port `AtomicWriter` from the FileTool package into this package. This is a behavioral port: keep the write-then-rename atomicity and the error mapping the same.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/AtomicWriter.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift`

Refer to eventplan.md § "Consolidation of the siblings": the Files capability gets `AtomicWriter`, and "Capabilities keep their own serialization where order is important (atomic file writes...)".

## Acceptance Criteria
- [x] A write is atomic: a reader sees the old content or the new content, never a partial file.
- [x] Encoding and permission behavior agree with the source.
- [x] `swift build` succeeds.

## Tests
- [x] Port `AtomicWriterTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [x] `swift test --filter AtomicWriterTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan

## Review Findings (2026-08-25 14:05)

> Scope: `review sha ae82449~1..ae82449` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift:260` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
