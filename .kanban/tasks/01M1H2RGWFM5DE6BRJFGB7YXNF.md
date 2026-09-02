---
assignees:
- claude-code
depends_on:
- 01M1H2QRY6PPQSS4ZKY7Q32M6H
position_column: todo
position_ordinal: '8180'
title: Post each mutating file verb's change set through the ambient ToolContext
---
## What
Ask 4, part 2 (UPSTREAM_ASKS.md). Hand the change set to the host as a `.progress` `OperationEvent` whose `detail` is the `fileChanges` envelope (`FileChangeSet.encodedOperationEventDetail()`).

**Why not the drain at the end of `MultiTool.call` that the ask names.** `FilesCapability.init` makes ONE `FileContext`, thus ONE `FileChangeJournal`, for the whole registry. `MultiToolConfiguration.liveContextLimit` lets 8 `runCode` calls run at once over that registry, and `MultiTool+Forking.swift` states one shared instance serves many sessions. A drain at the end of call A would take the changes call B recorded and post them under A's token. The ACP host would then put `tool_call_update.locations` on the wrong tool call. So each mutating VERB posts its own changes, through the `ToolContext` the engine bound around that inner call. `ToolContext.post(_:)` re-stamps the event with the OUTER `runCode` run's `tool`, `op` and `completionToken` (see `RunBinding.invoke` doc), so the host sees the same event shape and the same correlation the ask describes. `Execute.swift:412-420` is the precedent for a verb that posts through its ambient context.

Changes:
- `Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeJournal.swift`: add `import FoundationModelsRouter` and `func commit(_ changes: [FileChange], through context: ToolContext?) async`. Rules: return at once when `isRecording == false` or `changes` is empty. When `context` is not `nil`, post ONE event: `OperationEvent(tool: context.tool, op: context.op, correlationID: context.completionToken, kind: .progress, detail: FileChangeSet(root: root, changes: changes).encodedOperationEventDetail())` through `context.post(_:)`, and retain nothing. When `context` is `nil` (a verb called on a bare session, or a direct call in a test), append the changes to `recorded` for `drain()`. Document the rule: a change is delivered to the session or kept for a host to drain, never both, so a long session does not grow the journal. Keep `record(_:)` and `drain()`.
- `Capabilities/Files/Write.swift`, `Edit.swift`, `Patch.swift`: read `let toolContext = ToolContext.current` ONE time at the top of `call(arguments:)` (the rule of eventplan.md § "The ambient context", as `Execute.call` does). Replace each `context.changes.record(...)` with a `commit`. `Patch` collects every change of every outcome into one array and commits once, so a patch that touches four files posts ONE event with four changes. The partial-failure path of `Patch` (Patch.swift:271-275) commits what landed before it returns its correction, as it records today.
- Documentation: `FilesCapability.init` and `MultiTool.Builder.withFiles` doc for `recordsChanges`, and the `FileChangeJournal.swift` header: the recorded changes reach the session as a `.progress` event with the `fileChanges` envelope, one event for each mutating verb call; `FileChangeSet.init(operationEventDetail:)` is how a host reads it.

## Acceptance Criteria
- [ ] `Write` mounted with `context.mount(write, as: .synchronous)` on a stub session context, given a recording capability, writes one file and the stub run records exactly one `.progress` event whose `detail` decodes with `FileChangeSet(operationEventDetail:)` to one `.add` change at the written path, with `root` equal to the capability's canonical root, and with `correlationID` equal to the outer context's `completionToken`.
- [ ] `Patch` mounted the same way, with a four-file envelope (add, update, delete, move), records ONE `fileChanges` event with four changes.
- [ ] `Edit` mounted the same way records one event with one `.modify` change that carries `oldContent` and `newContent`.
- [ ] After each delivered event, `drain()` on the capability's journal is empty.
- [ ] A verb called with no ambient context (a direct call, as `FileChangeSetTests` does) still records into the journal, and every existing test in `FileChangeSetTests`, `FilesWriteTests`, `FilesEditTests` and `FilesPatchTests` stays green with no change.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/FileChangeEventTests.swift`. Get the context with `makeStubRun()` (`Fixtures/StubRouterFixtures.swift`), mount each verb with `context.mount(verb, as: .synchronous)` as `FilesCapabilityTests.aFileVerbMountedByTheSessionAnswersInline` does, and read events with `recordedOperationEvents(of: run, ofKind: .progress, correlatedTo: context.completionToken)` (StubRouterFixtures.swift:484). One test for each criterion above.
- [ ] Run `swift test --filter "FileChangeEvent|FileChangeSet|FilesWrite|FilesEdit|FilesPatch"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-4 #upstream-asks