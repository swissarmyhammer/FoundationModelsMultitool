---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m78y6t09ay2pxjhq5qjx9t2h
  text: |-
    ### review — clean
    - evidence: swift test, 2891 tests in 258 suites passed. review sha HEAD~1..HEAD (e9715ee1): 0 findings, 1 refuted, 7 validator runs, 0 failed.
    - next: none. The task is in done.
  timestamp: 2026-11-12T22:31:43.881132+00:00
position_column: done
position_ordinal: fffffffa80
title: The mutating file verbs post one display diff for each changed file
---
## What
Request from testudoapp-75. No code in the family posts `ToolDisplayEvent` content `.diff(path:oldText:newText:)`. Thus the Testudo chat shows only a text result when the agent writes or edits a file, and never the diff.

- `FileChangeJournal.commit(_:through:)` (Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeJournal.swift): under an ambient context, it posts one `.contentChunk(.diff(...))` for each change through `ToolContext.emit(chunk:)`. It does this also when the journal does not record.
- New `FileChangeJournal.displayDiff(of:)`: add/copy gives oldText nil; modify gives both texts; move gives the destination path; delete gives the old text and an empty new text. A side that exists with no text (binary) gives no diff.
- New `FileChangeJournal.capturesChanges(through:)`: Write, Patch and Delete capture the old text when the journal records or when the call has an ambient context.

## Acceptance Criteria
- [x] A write of a new file posts one diff with oldText nil.
- [x] An edit posts one diff with the old and the new text.
- [x] A failed write posts no diff.
- [x] A patch posts one diff for each file, in order. A delete posts one diff.
- [x] A write in a runCode snippet posts its diff under the runCode run.

## Tests
- [x] New Tests/FoundationModelsMultitoolTests/FileChangeDisplayTests.swift. `RecordingEventSink` keeps the display events.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #step1