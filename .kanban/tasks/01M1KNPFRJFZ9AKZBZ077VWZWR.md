---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Record Ask 4 as answered in UPSTREAM_ASKS.md, and name the carrier that answered it
---
## What
`UPSTREAM_ASKS.md` Ask 4 ("make the per-call file-change record public and drain it at the end of each call") still reads as an open request, with its evidence pinned at the old revision e8c91a6. Both halves are answered now, and a reader of that file cannot tell:

- Part (1), make `FileChange`/`FileChangeSet` public: done. They are public and `Codable` (Capabilities/Files/FileChangeSet.swift).
- Part (2), hand the set to the host: done, and in a shape the ask's own text did not name. The ask proposed a drain at the end of `MultiTool.call` through the captured `RunBinding`. What landed instead is per-verb delivery at journal commit, two ways: the `.progress` `OperationEvent` whose `detail` is the `fileChanges` envelope, and — task ^n313gma — the same envelope as a `ToolCallAttachment` through `ToolContext.attach(_:)`, which reaches a host live as `SessionEvent.toolCallReport`.

The file also states "Today no live event carries the touched paths", which is no longer true.

## Change
Rewrite Ask 4 as answered: what was asked, what landed, and the public names a host reads it by — `FileChangeSet`, `FileChangeSet.operationEventDetailKey` (the envelope key AND the attachment's `schemaName`), `encodedOperationEventDetail()`, `init(operationEventDetail:)`. Say why the delivery is per verb call rather than a drain at the end of `runCode` (one journal serves several concurrent `runCode` calls, so a drain would post call B's changes under call A's correlation — `FileChangeJournal.swift` carries that reasoning already).

Documentation only. No behavior changes, so no new test.

## Why
The ask file is the record the sibling packages read to learn what this package will and will not give them. An answered ask that still reads as open sends the next reader of FoundationModelsACPAgent looking for a seam that is already there.
