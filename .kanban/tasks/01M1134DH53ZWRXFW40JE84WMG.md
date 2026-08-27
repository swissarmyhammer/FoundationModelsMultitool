---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11vr71erewzyzq0g8t75526
  text: |-
    Research and implementation notes:
    - `Execute.call` read `ToolContext.current` with a `guard` and answered `noSessionCorrection` when it was `nil`. The three helpers `report`, `reportOutput` and `postTerminal` took a non-optional `ToolContext`.
    - Change: `call` reads the context as an optional. The `commandID` is `context?.completionToken ?? SessionMailbox.makeCompletionToken()`. The three helpers take `ToolContext?`. `reportOutput` posts through `context?.progress`. `postTerminal` returns at once when the context is `nil`. The stream pump is unchanged, so the store gets the same lines on both paths.
    - `noSessionCorrection` is deleted. The header comment and the doc comment of `call` state the two paths.
    - `ShellRunner.Request.completionToken` doc comment carries the one new sentence.
    - README has a "Layering" section before "Usage".
    - Tests: `ShellExecuteTests` replaces the `noSessionCorrection` case with a no-context `printf` case that reads the run back with `GetLines`. The suite doc comment no longer says every test binds a context.
    - `IntegrationTests/.../ShellBareSessionTests.swift` mounts `ShellCapability().tools` on `LanguageModelSession(model: SystemLanguageModel.default, tools:)`, asks for `echo bare`, and asserts the reply carries `bare`. It skips with a note when the system model is not available. `swift build --package-path IntegrationTests --build-tests` compiles it.
    - The repo holds no swift-format or swiftformat config file, so no formatter ran.
  timestamp: 2026-08-27T14:59:56.590159+00:00
- actor: claude-code
  id: 01m11vr91pjh14dpv2xs31ptnc
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift, Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift, Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellBareSessionTests.swift, README.md. `swift build` ok; `swift test --filter ShellExecuteTests` 23 tests passed; `swift build --package-path IntegrationTests --build-tests` ok.
    - next: run the full `swift test`, then commit and review.
  timestamp: 2026-08-27T14:59:58.646544+00:00
- actor: claude-code
  id: 01m11vsc9tzch8sfh0r37sjk64
  text: |-
    ### test — green
    - evidence: swift test — 1203 tests in 87 suites passed, 0 failed, 0 skipped, exit 0; swift build --package-path IntegrationTests --build-tests ok
    - next: commit
  timestamp: 2026-08-27T15:00:34.746718+00:00
- actor: claude-code
  id: 01m11vss2xqdnw2tdt4vvaevx1
  text: |-
    ### commit — changed
    - evidence: 0f42c9d feat(shell): run tools.shell.execute to completion on a bare LanguageModelSession
    - next: review HEAD~1..HEAD
  timestamp: 2026-08-27T15:00:47.837772+00:00
- actor: claude-code
  id: 01m11vz860n7x1r9zt5n3qrj5r
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings, 0 confirmed, 0 refuted; 4 files reviewed (README.md has no validator, .kanban/ is ignored)
    - next: move to done
  timestamp: 2026-08-27T15:03:47.136318+00:00
- actor: claude-code
  id: 01m11vze63snetq15nj9z7wpsc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — Execute.swift, ShellRunner.swift, ShellExecuteTests.swift, ShellBareSessionTests.swift, README.md
    - test: green — swift test 1203 tests in 87 suites passed; IntegrationTests build ok
    - commit: 0f42c9d
    - review: clean — 0 findings on HEAD~1..HEAD; task moved to done
  timestamp: 2026-08-27T15:03:53.283789+00:00
position_column: done
position_ordinal: ff9280
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
- [x] `Execute(runner:).call(arguments:)` with no bound `ToolContext` runs the command and returns the report with the run's id, status, and output tail.
- [x] After that call, `GetLines` and `GrepHistory` on the same `ShellState` read the run's output.
- [x] Under a bound `ToolContext`, the behavior is unchanged: `commandID == context.completionToken`, and the events post.
- [x] `noSessionCorrection` no longer exists.
- [x] `README.md` has the "Layering" section.
- [x] `swift build` succeeds.

## Tests
- [x] Extend `Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift`: a no-context case that runs `printf` and asserts the report, then reads it back with `GetLines`. Remove the case that asserts `noSessionCorrection`.
- [x] Add a gated case in `IntegrationTests/`: mount `ShellCapability().tools` on `LanguageModelSession(model: .default, tools:)` with no Router, prompt the model to run `echo bare`, and assert the answer carries `bare`.
- [x] `swift test --filter ShellExecuteTests` passes.
- [x] Full `swift test` passes.

## Workflow
- Use `/tdd` — write the no-context case first, then remove the guard. #eventplan #phase-4