---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1h90gaq6zn1wqsqab1x9y2w
  text: |-
    ### research
    - `FileChangeJournal.commit(_:through:)` (Sources/.../Files/FileChangeJournal.swift:131) returns at once when the journal is disabled or the change list is empty. With a context it posts ONE `.progress` event. With no context it keeps the changes for `drain()`.
    - `Write.call` and `Edit.call` read `ToolContext.current` one time at the top. `Write` commits only after `AtomicWriter.write` lands. A path the guard refuses returns a correction before the commit. `Edit` commits only in the `.applied` branch; an unresolved find returns `unresolvedResult` and commits nothing.
    - A `MultiTool` run binds the ambient context to each inner `tools.*` call through `RunBinding.invoke` -> `context.mount(tool, as: innerMount)`. `SandboxGlobalsTests.runSnippet` shows the set-up: `ToolContext.$current.withValue(context) { multiTool.call(...) }`, then `recordedOperationEvents(of: stub, ofKind: .progress)`.
    - `notify("text")` posts a `.progress` event with `detail == "text"` after the snippet ends (the outbox flush).
    - The registry keys the verbs by path: `registry.tools["files.write"] as? Write` gives the journal through `write.context.changes`.
    - The test file the card names as `FileChangeRunCodeTests` does not exist. `FileChangeEventTests.swift` holds the closest set-up (direct verb mounts). The new suite runs snippets through a `MultiTool` as the card asks.
    - Plan: add `Tests/FoundationModelsMultitoolTests/FileChangeEventAbsenceTests.swift` with five tests, one for each criterion. No production change is expected, because each negative case already has a guard in the code.
  timestamp: 2026-09-02T14:40:16.215239+00:00
- actor: claude-code
  id: 01m1h9496eqy1wvxfcw96p8t8y
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/FileChangeEventAbsenceTests.swift (new, 5 tests, one for each criterion). `swift test --filter "FileChangeEventAbsence"`: 5 tests in 1 suite passed. No production change: each negative case already has a guard, and the tests prove it. The one build warning is the pre-existing mlx bundle "missing creator" line, not from this change.
    - next: run the full `swift test`, then commit, then review.
  timestamp: 2026-09-02T14:42:19.982808+00:00
depends_on:
- 01M1H2RGWFM5DE6BRJFGB7YXNF
position_column: doing
position_ordinal: '80'
title: Pin the cases where no file-change event is posted
---
## What
Ask 4, part 4 (UPSTREAM_ASKS.md). The negative half of the contract of `FileChangeJournal.commit(_:through:)`: when nothing is posted, and where the change goes instead. This task adds tests, and it changes production code only where a test proves a gap.

## Acceptance Criteria
- [x] A snippet that only reads (`tools.files.read`, `tools.files.glob`, `tools.files.grep`) under a recording capability leaves no `fileChanges` event (no `.progress` event whose `detail` decodes with `FileChangeSet(operationEventDetail:)`).
- [x] A snippet that writes under a NON-recording capability (`recordsChanges: false`) leaves no `fileChanges` event, and the journal's `drain()` is empty.
- [x] A write that does not land (a write refused by the path guard, or an `edit` whose anchor does not resolve) leaves no `fileChanges` event.
- [x] A `MultiTool` called with NO ambient `ToolContext` (no `withValue`), over a recording capability, whose snippet writes one file: no session receives anything, and the journal keeps the change for `drain()` (one `.add` change).
- [x] A `notify("text")` call in the same snippet as a write leaves a `.progress` event whose `detail` is `"text"`, and `FileChangeSet(operationEventDetail:)` on that detail is `nil`: the two kinds of progress event are told apart by the envelope alone.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/FileChangeEventAbsenceTests.swift`. Same set-up as `FileChangeRunCodeTests`: `MultiTool.Builder().withFiles(root:recordsChanges:)`, `makeStubRun()`, `recordedOperationEvents(of:ofKind:correlatedTo:)`. To reach the journal, take the `Write` verb out of `registry.tools["files.write"]` with `as? Write` and read `write.context.changes`. One test for each criterion above.
- [x] Run `swift test --filter "FileChangeEventAbsence"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #upstream-asks #ask-4