---
assignees:
- claude-code
depends_on:
- 01M0WWPC0PMTEJGP2MHGX95ZTX
- 01M0WWNWDG0SPX34065AZ7JW8H
- 01M0WWPWHFXSDJKH2GYZCR6QZ8
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8680'
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