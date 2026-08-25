---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0x9k99981tc4hvbakfrqkvn
  text: |-
    Research findings:
    - The source `EditEngine.swift` is pure and IO-free. It does not do writes and it does not use diagnostics types. The diagnostics fold is only in the sibling `EditFile.swift` result envelope (`EditResult` has `FileDiagnostics`).
    - `EditOutcomeProjection.swift` uses wire types `EditOutcome`, `EditCandidate`, `EditContextLine`, `EditNearMiss`, `EditDiffLine`. The sibling declares them in `Operations/EditFile.swift`. This package does not have them. The port must include them, or the projection cannot compile. Plan: put them in the ported `EditOutcomeProjection.swift`, without `EditResult` (it holds the diagnostics field; decision 2026-08-11).
    - All engine dependencies are in place in `Capabilities/Files/`: `Hashline.parseAnchor/resolveAnchor/splitLines/tag`, `EditMatch.findMatch/byteOffsets/lineNumber/normalize/unicodeNormalize/foldConfusables`, `LineDiff.changes`. Case shapes match the sibling.
    - Package convention: internal access (not `public`), a `//` header block that names the sibling port, `// periphery:ignore` only where periphery really reports dead code.
    - About the acceptance item "Writes go through the ported `AtomicWriter`": the engine makes no writes, the same as the sibling. The edit verb card (^v5xap97) routes the committed content through `AtomicWriter`. This port adds no write path that goes around `AtomicWriter`.
    - Stale comments to correct: `EditMatch.swift` and `AtomicWriter.swift` headers and four `EditMatch` doc notes say this card has not landed. They get an update in this card.
    - Test plan (/tdd): port `EditEngineTests.swift` first, add a new `EditOutcomeProjectionTests.swift` for the projection (the sibling has no suite for it), watch RED, then port the sources to GREEN.
  timestamp: 2026-08-25T20:25:42.953688+00:00
- actor: claude-code
  id: 01m0xa1cqhwd10rah7nmg9wz0q
  text: |-
    Implementation landed (/tdd, RED then GREEN):
    - Tests first: ported `EditEngineTests.swift` (24 tests) and wrote the new `EditOutcomeProjectionTests.swift` (11 tests). RED was confirmed: `swift build --build-tests` failed with "cannot find 'EditEngine' / 'EditOutcomeProjection' in scope".
    - Then ported `EditEngine.swift` and `EditOutcomeProjection.swift` into `Sources/FoundationModelsMultitool/Capabilities/Files/`, internal access, package header style. The projection file also carries the five wire types (`EditOutcome`, `EditCandidate`, `EditContextLine`, `EditNearMiss`, `EditDiffLine`) from the sibling's `Operations/EditFile.swift` — without them the projection cannot compile. `EditResult` is NOT ported: it holds the diagnostics fold (`FileDiagnostics`), and the port carries no diagnostics types (decision 2026-08-11).
    - The engine keeps the shape-inferred dispatch (explicit `edits` array wins; equal-count zip; single-replace broadcast) and the in-band corrective posture (`Normalization.corrective` — no throw for a payload that cannot resolve).
    - The engine reuses the ported layers: `Hashline` (anchor rung, line model), `EditMatch` (`findMatch`, `byteOffsets`, `lineNumber`, `normalize`, `unicodeNormalize`, `foldConfusables`), and `LineDiff.changes` (near-miss diff, suffix trim off).
    - Stale cross references got an update: `EditMatch.swift` (header and three "Kept visible" notes) and `AtomicWriter.swift` header plus `AtomicWriterTests` doc no longer say this card has not landed; the write path consumers are named as ^p238zzp and ^v5xap97.
    - Acceptance item "Writes go through the ported AtomicWriter": the engine is IO-free, the same as the sibling — it makes no writes at all, so no write path goes around `AtomicWriter`. The edit verb card (^v5xap97) commits the engine's content through `AtomicWriter`.
    - Verification: `swift build --build-tests` succeeds with zero warnings; `swift test --filter EditEngineTests --filter EditOutcomeProjectionTests` = 38 tests pass; full `swift test` = 804 tests in 62 suites pass, zero failures, zero skips; `periphery scan --skip-build --index-store-path .build/out` reports nothing in the ported files (all listed warnings pre-exist in other files), so no `// periphery:ignore` was necessary.
  timestamp: 2026-08-25T20:33:25.233636+00:00
- actor: claude-code
  id: 01m0xa1jdyxq1nz2s7fpf45n54
  text: |-
    ### implement — changed
    - evidence: 7 files — new: Sources/FoundationModelsMultitool/Capabilities/Files/EditEngine.swift, Sources/FoundationModelsMultitool/Capabilities/Files/EditOutcomeProjection.swift, Tests/FoundationModelsMultitoolTests/EditEngineTests.swift, Tests/FoundationModelsMultitoolTests/EditOutcomeProjectionTests.swift; comment-only updates: Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift, Sources/FoundationModelsMultitool/Capabilities/Files/AtomicWriter.swift, Tests/FoundationModelsMultitoolTests/AtomicWriterTests.swift. Tests: swift test = 804 tests in 62 suites, all pass; targeted filter run = 38 tests pass; swift build --build-tests clean.
    - next: /review moves the task through the review column.
  timestamp: 2026-08-25T20:33:31.070684+00:00
- actor: claude-code
  id: 01m0xa47gf0cf2qzh5cknzdxfz
  text: |-
    ### test — green
    - evidence: swift test — 804 tests, 62 suites. 0 failed. 0 skipped.
    - note: 1 warning seen. It is the known mlx-swift notice: "missing creator for mutated node". This is a known issue. No action taken on it.
    - next: none. The build is clean.
  timestamp: 2026-08-25T20:34:58.191125+00:00
depends_on:
- 01M0WWPC0PMTEJGP2MHGX95ZTX
- 01M0WWNWDG0SPX34065AZ7JW8H
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: doing
position_ordinal: '80'
title: Port EditEngine and EditOutcomeProjection into Capabilities/Files
---
## What
Port `EditEngine` and `EditOutcomeProjection` from the FileTool package into this package. Keep the shape-inferred dispatch: the engine reads the payload shape and selects the edit strategy. eventplan.md § "Consolidation of the siblings" names "the shape-inferred dispatch of `EditEngine`" as part of the capability.

- Sources: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/EditEngine.swift` and `.../EditOutcomeProjection.swift`
- Targets: the same file names in `Sources/FoundationModelsMultitool/Capabilities/Files/`

Keep the corrective posture: a payload that cannot resolve comes back in-band. It is never thrown (eventplan.md § "Consolidation of the siblings").

## Acceptance Criteria
- [ ] The engine selects the same strategy for the same payload shape as the source.
- [ ] A payload that cannot resolve gives a corrective result in-band. It does not throw.
- [ ] Writes go through the ported `AtomicWriter`.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `EditEngineTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter EditEngineTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan