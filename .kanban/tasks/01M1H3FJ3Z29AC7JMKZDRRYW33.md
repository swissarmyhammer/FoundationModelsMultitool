---
assignees:
- claude-code
depends_on:
- 01M1H2RGWFM5DE6BRJFGB7YXNF
position_column: todo
position_ordinal: '8580'
title: Pin the cases where no file-change event is posted
---
## What
Ask 4, part 4 (UPSTREAM_ASKS.md). The negative half of the contract of `FileChangeJournal.commit(_:through:)`: when nothing is posted, and where the change goes instead. This task adds tests, and it changes production code only where a test proves a gap.

## Acceptance Criteria
- [ ] A snippet that only reads (`tools.files.read`, `tools.files.glob`, `tools.files.grep`) under a recording capability leaves no `fileChanges` event (no `.progress` event whose `detail` decodes with `FileChangeSet(operationEventDetail:)`).
- [ ] A snippet that writes under a NON-recording capability (`recordsChanges: false`) leaves no `fileChanges` event, and the journal's `drain()` is empty.
- [ ] A write that does not land (a write refused by the path guard, or an `edit` whose anchor does not resolve) leaves no `fileChanges` event.
- [ ] A `MultiTool` called with NO ambient `ToolContext` (no `withValue`), over a recording capability, whose snippet writes one file: no session receives anything, and the journal keeps the change for `drain()` (one `.add` change).
- [ ] A `notify("text")` call in the same snippet as a write leaves a `.progress` event whose `detail` is `"text"`, and `FileChangeSet(operationEventDetail:)` on that detail is `nil`: the two kinds of progress event are told apart by the envelope alone.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/FileChangeEventAbsenceTests.swift`. Same set-up as `FileChangeRunCodeTests`: `MultiTool.Builder().withFiles(root:recordsChanges:)`, `makeStubRun()`, `recordedOperationEvents(of:ofKind:correlatedTo:)`. To reach the journal, take the `Write` verb out of `registry.tools["files.write"]` with `as? Write` and read `write.context.changes`. One test for each criterion above.
- [ ] Run `swift test --filter "FileChangeEventAbsence"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #upstream-asks #ask-4