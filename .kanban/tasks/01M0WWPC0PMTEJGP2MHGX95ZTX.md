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
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
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