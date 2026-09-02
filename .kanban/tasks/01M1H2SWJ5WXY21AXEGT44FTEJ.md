---
assignees:
- claude-code
depends_on:
- 01M1H2RGWFM5DE6BRJFGB7YXNF
position_column: todo
position_ordinal: '8380'
title: Prove the file-change event end to end through runCode, with concurrent calls
---
## What
Ask 4, part 3 (UPSTREAM_ASKS.md). The verb-level post (task "Post each mutating file verb's change set through the ambient ToolContext") must reach the host through the whole `runCode` route: a snippet calls `tools.files.write`, the inner call travels `RunBinding.invoke` and the engine mount, and the `fileChanges` event lands on the OUTER run's correlation. This task adds no production code unless a test proves a gap. If a test finds a gap (for example the mount for a `@Generable`-output tool does not forward the post), fix it in `Sources/FoundationModelsMultitool/Invocation/RunBinding.swift` and say so in the commit.

## Acceptance Criteria
- [ ] A `MultiTool` over `MultiTool.Builder().withFiles(root:recordsChanges: true).buildRegistry()`, called inside `ToolContext.$current.withValue(context)` with a snippet that calls `tools.files.write` once, leaves exactly one `.progress` event in the stub run whose `detail` decodes to one `.add` change at the written path, with `correlationID` equal to the outer `context.completionToken`.
- [ ] That event is in the recorder before `MultiTool.call(arguments:)` returns (read the events right after the call, with no wait).
- [ ] A snippet that calls `tools.files.patch` with a three-file envelope leaves ONE `fileChanges` event with three changes.
- [ ] Two `runCode` calls that run at the same time over ONE `MultiTool` (two stub run contexts, two `Task`s, each snippet writes a different file) leave two `fileChanges` events, and each event carries only its own path under its own `completionToken`.
- [ ] The rendered `runCode` result text of a recording capability is equal to the text of a non-recording capability for the same snippet (the model never sees the change set).

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/FileChangeRunCodeTests.swift`. Run the snippet as `SandboxGlobalsTests.runSnippet(_:under:)` does (`ToolContext.$current.withValue(context) { try await multiTool.call(arguments:) }`). Read events with `recordedOperationEvents(of: run, ofKind: .progress, correlatedTo: context.completionToken)`. One test for each criterion above. For the concurrent case, gate the two snippets on a shared `ReleaseGate` (`Tests/FoundationModelsMultitoolTests/Support/ReleaseGate.swift`) so both are in flight together before either writes.
- [ ] Run `swift test --filter "FileChangeRunCode|FileChangeEvent"` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #ask-4 #upstream-asks