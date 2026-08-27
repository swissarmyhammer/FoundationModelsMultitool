---
assignees:
- claude-code
position_column: todo
position_ordinal: '9380'
title: Make tools.shell.execute run on a bare LanguageModelSession
---
## What
The constituent verbs are plain `FoundationModels.Tool` conformers, and they must work in a bare `LanguageModelSession` with no Router. `BackgroundTool` means nothing without Router's engine, and that is correct. But `Execute` refuses to run with no ambient context: `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift:212` returns `noSessionCorrection` when `ToolContext.current` is `nil`. Its doc comment says the reason: "The verb mints no identifier." Change that.

- Modify `Execute.call(arguments:)`: when `ToolContext.current` is `nil`, mint the `commandID` locally (a ULID; `SessionMailbox.makeCompletionToken()` gives one, or use `ULID()` directly) and run the request to completion. The store records the run under that id, so `tools.shell.getLines` and `grepHistory` read it as usual. Posts through the `nil` context stay no-ops. The rendered report is the same text the terminal detail carries when mounted.
- Delete `noSessionCorrection` and the doc-comment paragraph "A call with no session runs nothing." Replace the paragraph with one that states the two paths: mounted under Router, the engine parks the run and the model gets the envelope; on a bare session, the verb runs to completion and returns the report.
- Do not change the `BackgroundTool` conformance. On Router it stays a background verb with `runKind: .process`.
- `ShellRunner.Request.completionToken` keeps its name. Add one sentence to its doc comment: with no session, this is a locally minted id, and no run-plane entry exists for it.
- Update `README.md`: add a short "Layering" section before "Usage" that states the three layers in a table — verb (`any Tool`, needs `FoundationModels` only) / Router `Hosting/` (context, events, elicitation, background) / MultiTool (`runCode`, `findAPIs`, the globals). State that each verb of files, shell, and MCP works on a bare `LanguageModelSession`, and that background is a property of the Router mount, not of the verb.

## Acceptance Criteria
- [ ] `Execute(runner:).call(arguments:)` with no bound `ToolContext` runs the command and returns the report with the run's id, status, and output tail.
- [ ] After that call, `GetLines` and `GrepHistory` on the same `ShellState` read the run's output.
- [ ] Under a bound `ToolContext`, the behavior is unchanged: `commandID == context.completionToken`, and the events post.
- [ ] `noSessionCorrection` no longer exists.
- [ ] `README.md` has the "Layering" section.
- [ ] `swift build` succeeds.

## Tests
- [ ] Extend `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`: a no-context case that runs `printf` and asserts the report, then reads it back with `GetLines`. Remove the case that asserts `noSessionCorrection`.
- [ ] Add a gated case in `IntegrationTests/`: mount `ShellCapability().tools` on `LanguageModelSession(model: .default, tools:)` with no Router, prompt the model to run `echo bare`, and assert the answer carries `bare`.
- [ ] `swift test --filter ShellExecuteTests` passes.
- [ ] Full `swift test` passes.

## Workflow
- Use `/tdd` — write the no-context case first, then remove the guard. #eventplan #phase-4