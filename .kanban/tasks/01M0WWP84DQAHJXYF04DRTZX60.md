---
assignees:
- claude-code
depends_on:
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: todo
position_ordinal: '8380'
title: Port FileChangeSet, LineDiff, and GitPatch into Capabilities/Files
---
## What
Port the change-record value layer from the FileTool package into this package.

- Sources, all in `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/`: `FileChangeSet.swift`, `LineDiff.swift`, `GitPatch.swift`
- Targets: the same file names in `Sources/FoundationModelsMultitool/Capabilities/Files/`

`FileChangeJournal` is NOT in this task. It calls `FileWalker.canonicalDirectory` and `FileWalker` reaches back to `FileContext`, so those three port together in the FileContext task.

`FileChangeSetTests` is NOT in this task either. It drives the journal through the `write`, `edit`, and `patch` verbs, so it ports in its own later task.

## Acceptance Criteria
- [ ] `LineDiff` computes the same diffs as the source.
- [ ] `GitPatch` renders the same patch text as the source.
- [ ] `FileChangeSet` compiles and keeps the source API for the journal and the later tests.
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `LineDiffTests.swift` and `GitPatchTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [ ] `swift test --filter LineDiffTests` passes.
- [ ] `swift test --filter GitPatchTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass.