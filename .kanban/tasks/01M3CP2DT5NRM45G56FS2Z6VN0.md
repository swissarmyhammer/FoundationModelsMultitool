---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: 'Tests: use RunOutput.decoded in FilesCrossOpFlowTests and FileChangeEventAbsenceTests'
---
## What
`FilesCrossOpFlowTests` and `FileChangeEventAbsenceTests` each hold a private copy of `decoded(_:from:)`. The shared helper `RunOutput.decoded(_:from:)` in `Tests/FoundationModelsMultitoolTests/Support/RunOutput.swift` does the same work. Task ^3332gzb added the shared helper. The duplication rule did not let that task edit these two files.

- Delete the private `decoded` function in each of the two files.
- Call `RunOutput.decoded(_:from:)` at each call site.

## Acceptance Criteria
- [ ] No test file holds its own copy of `decoded(_:from:)`.
- [ ] `swift test --filter "FilesCrossOpFlowTests|FileChangeEventAbsenceTests"` passes.

## Tests
- [ ] Run `swift test`. All pass. #web