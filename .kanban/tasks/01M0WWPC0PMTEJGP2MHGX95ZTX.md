---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0x6p7wzvfmmhwj8v6708y6d
  text: |-
    Work log for the port:
    - I copied the fixture to Tests/FoundationModelsMultitoolTests/FilesGoldens/edit-match-golden.json. The SHA-1 of the copy is equal to the SHA-1 of the source. Package.swift already has the one .copy("FilesGoldens") rule from the Hashline task. I did not add a second rule. I did not add a rule for Fixtures/.
    - TDD order: I ported EditMatchTests.swift first. The test run failed with "cannot find 'EditMatch' in scope" (RED). Then I ported EditMatch.swift, and the 30 tests passed (GREEN).
    - Changes from the source in the test file: @testable import FoundationModelsMultitool; the fixture subdirectory is "FilesGoldens"; I gave names to the numeric literals (nearMissProbeLength, nearMissCap, survivingNearMissCount, ambiguousOccurrenceCount) because the magic-number rule for Swift Testing suites has no test exemption.
    - Changes from the source in EditMatch.swift: the type is internal, the same as Hashline, PathGuard, and PathCorrective; the header matches the style of the files in Capabilities/Files; I gave the name minimumAnchorLineCount to the literal 2 in locateAnchor (the only expression-position magic number); the notes that said "Visible to EditEngine" now point to the edit-engine card ^87tzkdp.
    - The scalar-based levenshtein stays separate from MultiTool's private Character-based levenshteinDistance. The two count different edit units, and the golden parity with the Rust crate requires scalar counts. The doc comment on levenshtein records this intentional fork.
    - Periphery (index store .build/out, --retain-public, tests excluded) reports no dead declaration in EditMatch.swift or EditMatchTests.swift. So the file has no periphery:ignore mark. The only periphery findings are pre-existing, in JSCInterpreter.swift and ToolAPIRenderer.swift, outside this change.
  timestamp: 2026-08-25T19:34:54.111279+00:00
- actor: claude-code
  id: 01m0x6p9rxfz379rhjjkvpemk7
  text: |-
    ### implement — changed
    - evidence: 3 new files — Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift, Tests/FoundationModelsMultitoolTests/EditMatchTests.swift, Tests/FoundationModelsMultitoolTests/FilesGoldens/edit-match-golden.json. `swift build` passes. `swift test --filter EditMatchTests` passes (30 tests). Full `swift test` passes (737 tests, 57 suites, 0 failures, 0 warnings).
    - next: /review
  timestamp: 2026-08-25T19:34:56.029482+00:00
- actor: claude-code
  id: 01m0x6rkcwqq6w7bmc5m271w1s
  text: |-
    ### test — green
    - evidence: swift test — 737 passed, 0 failed, 0 skipped; 1 warning found (known pre-existing mlx-swift "missing creator for mutated node", not chased); no failures to fix.
    - next: ready for review.
  timestamp: 2026-08-25T19:36:11.420755+00:00
- actor: claude-code
  id: 01m0x78pnvsaaepqc11zxn68mp
  text: |-
    ### review — findings
    - evidence: 4 findings — Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:611, Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:612, Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:613, Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:615 (scope: review sha 859e4bf~1..859e4bf, backend local; counts findings=4 confirmed=18 refuted=1 failed=0)
    - next: replace each magic number in EditMatch.swift with a named constant, then run the review again
  timestamp: 2026-08-25T19:44:59.067242+00:00
- actor: claude-code
  id: 01m0x7f8s9k1zzjek36fd5sc6w
  text: |-
    Fix for the four magic-number findings:
    - I gave a name to each Unicode scalar value in the confusableFoldings table. The names follow the shape of the control-scalar constants in PathGuard: a private static let of type UInt32, with a doc comment that states the character. The names are hyphenBlockStart (U+2010), hyphenBlockEnd (U+2015), minusSign (U+2212), singleQuoteBlockStart (U+2018), singleQuoteBlockEnd (U+201B), doubleQuoteBlockStart (U+201C), doubleQuoteBlockEnd (U+201F), noBreakSpace (U+00A0), spaceBlockStart (U+2000), spaceBlockEnd (U+200A), narrowNoBreakSpace (U+202F), mediumMathematicalSpace (U+205F), and ideographicSpace (U+3000).
    - The confusableFoldings table now uses only the named constants. The doc comment on the table points to the constant names, not to bare code points.
    - I examined the full file for other unnamed literals outside {0, 1, -1, 100}. There are none. The values 0.85, 0.10, 1e-4, 1.0, 2, 3, 0x0A, and 0x0D already have names (fuzzyAcceptThreshold, fuzzyRunnerUpMargin, fuzzyBoundaryEpsilon, confidentMatchScore, minimumAnchorLineCount, maxNearMisses, newlineByte, carriageReturnByte).
    - The behavior did not change. swift build passes. swift test --filter EditMatchTests passes (30 tests). The one build warning is the known mlx-swift "missing creator for mutated node" warning, which the test record on this card already names as pre-existing.
  timestamp: 2026-08-25T19:48:34.217401+00:00
- actor: claude-code
  id: 01m0x7fcpqwvgcygs06hb57xz6
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift. All four magic-number findings are fixed and checked in the description. `swift build` passes. `swift test --filter EditMatchTests` passes (30 tests).
    - next: /review
  timestamp: 2026-08-25T19:48:38.231366+00:00
- actor: claude-code
  id: 01m0x7he3jr137vmwzejtbfj12
  text: |-
    ### test — green
    - evidence: swift test — 737 tests, 57 suites, 0 failures, 0 skipped. 1 warning found: the known mlx-swift "missing creator for mutated node" notice (pre-existing, not chased). No new warnings.
    - next: none
  timestamp: 2026-08-25T19:49:45.202755+00:00
- actor: claude-code
  id: 01m0x7rtj49bvpff9qxz064z6y
  text: |-
    ### review — clean
    - evidence: `review sha eae26cd~1..eae26cd` (local backend) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. All 4 prior findings are checked.
    - next: none — task moved to done.

    step: review
    outcome: clean
    evidence: 0 findings (7 attempted, 0 failed) on eae26cd~1..eae26cd; 4/4 prior findings checked
    task: ^gx95ztx
  timestamp: 2026-08-25T19:53:47.332356+00:00
- actor: claude-code
  id: 01m0x7safnett5cy418jt15dsm
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — named each Unicode scalar constant in the confusable-fold table of EditMatch.swift
    - test: green — swift test, 737 tests in 57 suites, 0 failed
    - commit: eae26cd (iteration 1: 859e4bf)
    - review: clean — review sha eae26cd~1..eae26cd, 0 findings, all 4 prior items checked
    - task landed in done
  timestamp: 2026-08-25T19:54:03.637368+00:00
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: done
position_ordinal: fb80
title: Port EditMatch into Capabilities/Files
---
## What
Port `EditMatch` from the FileTool package into this package. This is the pure matching layer under `EditEngine`. It has no file IO and no context dependency, so it ports alone.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/EditMatch.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift`

Fixture: `EditMatchTests` loads `edit-match-golden.json` through `Bundle.module` (source lines 63-68). Copy `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/Fixtures/edit-match-golden.json` into `Tests/FoundationModelsMultitoolTests/FilesGoldens/`, and add `.copy("FilesGoldens")` to the test-target `resources` in `Package.swift` if it is not present yet. Never add a resource rule for the existing `Fixtures/` directory — it holds compiled `.swift` files.

## Acceptance Criteria
- [ ] Match selection, ambiguity detection, and near-miss reporting agree with the source.
- [ ] The golden fixture loads through `Bundle.module` from `FilesGoldens`.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `EditMatchTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter EditMatchTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan

## Review Findings (2026-08-25 14:37)

> Scope: `review sha 859e4bf~1..859e4bf` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:611` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:612` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:613` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift:615` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
