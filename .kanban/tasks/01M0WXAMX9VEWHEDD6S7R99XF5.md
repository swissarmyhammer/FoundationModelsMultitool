---
assignees:
- claude-code
depends_on:
- 01M0WWSCM9CHRT7B5AWVB4DVZP
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '9280'
title: Port FileChangeSetTests after the mutating verbs exist
---
## What
Port `FileChangeSetTests` after the mutating verbs exist, because the tests drive the journal through `write`, `edit`, and `patch`.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/FileChangeSetTests.swift`
- Target: `Tests/FoundationModelsMultitoolTests/FileChangeSetTests.swift`

Adapt the calls: the source uses `WriteFile` (line 31), `EditFile` (line 49), and `PatchFiles` (line 58); the port uses the `Write`, `Edit`, and `Patch` verbs. The source also reads `PatchFiles.changeKinds` (line 325). That table lives in `Sources/FoundationModelsMultitool/Capabilities/Files/Patch.swift` — confirm the patch-verb task carried it, and add it there if it is absent.

## Acceptance Criteria
- [ ] The journal records changes only in recording mode, as the source proves (source lines 208, 505, 506).
- [ ] A drained `FileChangeSet` renders the same patch text as the source.
- [ ] `swift build` succeeds.

## Tests
- [ ] `swift test --filter FileChangeSetTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then adjust the code to make them pass. #phase-3 #eventplan