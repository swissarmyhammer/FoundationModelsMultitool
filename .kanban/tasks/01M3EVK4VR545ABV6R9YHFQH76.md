---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ff5xry5dggrtymzfv9v6af
  text: |-
    ### implement — research and compile errors
    - Compile errors that `swift build --build-tests` reported against Router `c208add`: 10 errors `value of type 'MultiTool' has no member 'turnWillBegin'` — 5 call sites in `RegistrySwapTests.swift` (lines 106, 137, 158, 175, 187) and 8 call sites in `SurfaceRefresherTests.swift` (lines 317, 336, 367, 403, 416, 464, 486, 513). The other files in the failure list (`SummaryBlockCapTests.swift`, `Support/CapabilityDiscoveryProbe.swift`, `SuspendedContextTests.swift`, `TestSupport.swift`, `ToolAPIRendererTests.swift`, `ToolInvokerTests.swift`, `ToolReturnLedgerTests.swift`) failed only because they compile in the same batch. They had no error of their own.
    - `MCPSessionSweepTests.swift` had `cancelCurrentTurn()` in a doc comment only. Router `c208add` names it `RoutedSession.cancel()` (`RoutedSession.swift:302`).
    - The build system warning `missing creator for mutated node ... mlx-swift_Cmlx.bundle` was there before this change. It is not a source warning.
    - The sibling checkout `../FoundationModelsRouter` is at `9ba19a6`, which is newer than the resolved pin. Read `.build/checkouts/FoundationModelsRouter` for the `c208add` API.
    - Tool note: the sah `files` `edit file` op replaces only the first match, also with `replace_all`. Do one edit per match.
  timestamp: 2026-09-26T18:21:00.062961+00:00
- actor: claude-code
  id: 01m3ffd1qr8grzhabx1jc595aa
  text: |-
    ### implement — changed
    - Test failures that `swift test` reported after the test target compiled (2 of 1797):
      1. `ScenarioFixtureTests` "the archive-rebuild fixture settles only after its delay, which outlasts runCode's inline settle grace": `integrationArchiveRebuildDelaySeconds` was 4, and commit `3ee0a2f` set `defaultInlineSettleGrace` to 5. Fix: the delay is now 10 s (two times the grace, the documented rule), and the doc comment in `Tests/Support/ScenarioGrading/ScenarioTools.swift` now says five seconds. The support module does not import the library, so the value stays a literal that `ScenarioFixtureTests` guards.
      2. `ShellSessionSweepTests` "the terminal event of a swept shell run carries the outcome .stopped" failed at line 279 (`status == .killed`) in the full run only. It passed alone 5 of 5 times. Cause: `ShellRunner.canceler` sent `killpg` and then wrote `.killed`. Under load the run body saw the death and wrote `.completed` first. Fix: the canceler now reads the pid, writes `.killed` with `completeIfRunning`, and then sends `killpg`. The doc comment tells why the order is load bearing.
    - Files: `Tests/FoundationModelsMultitoolTests/RegistrySwapTests.swift` (renames, new test `swapBetweenTwoSubmissionsOfOneAnswerGivesTheRepairHint`, shared `citiesSnippet`), `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift` (renames), `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift` (doc reference `RoutedSession.cancel()`), `Tests/Support/ScenarioGrading/ScenarioTools.swift`, `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`.
    - The new test passed at its first run: the library already applies the staged registry in `submissionWillBegin()`. It pins the behaviour that the hook now also runs inside one answer.

    ### test — green
    - evidence: `swift build --build-tests` — 0 errors, no new warnings (the one build-system warning on the mlx bundle was there before). `swift test` — 1797 tests in 145 suites passed, 0 failed, 3 full runs. XCTest: 0 tests. `rg -w 'turnWillBegin|TurnBoundaryTool|cancelCurrentTurn' Tests` — no match.
    - next: commit, then review HEAD~1..HEAD.
  timestamp: 2026-09-26T18:24:53.496944+00:00
- actor: claude-code
  id: 01m3ffkrdhds638a55tjxbs6ez
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — findings 0, confirmed 0, refuted 0, attempted 7, failed 0, skipped 0. 5 files reviewed; the 2 `.kanban/` files are excluded by `.reviewignore`. No prior `## Review Findings` section. The Swift dead-code rule could run, because the test target now compiles.
    - next: the task moved to `done`.

    ### finish iteration 1 — clean
    - implement: changed — 5 files: `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`, `Tests/FoundationModelsMultitoolTests/RegistrySwapTests.swift`, `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift`, `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift`, `Tests/Support/ScenarioGrading/ScenarioTools.swift`. Correction to the first comment: the build reported the `turnWillBegin` error at 13 call sites (5 + 8), and the sorted list showed fewer lines.
    - test: green — `swift build --build-tests` 0 errors, no new warnings; `swift test` 1797 tests in 145 suites passed, 3 full runs.
    - commit: changed — `610bff7 test(router): build and pass the unit tests against the work-queue Router c208add`.
    - review: clean — 0 findings on `HEAD~1..HEAD`.
  timestamp: 2026-09-26T18:28:33.329869+00:00
depends_on:
- 01M3ETSEG8QR1Y31J1FB1A2YQB
position_column: done
position_ordinal: ffec80
title: Make the unit test target build and pass against the work-queue Router
---
## What
After the library task, `swift build --build-tests` can still fail in `Tests/FoundationModelsMultitoolTests` against Router `c208add`. Upstream commit `2f4707f` already gave the stub container a `TokenCounter` (`StubWordTokenCounter`) and the stub metadata `max_position_embeddings`, and it already changed the timeout and mount names in the tests.
- [x] In `RegistrySwapTests.swift` (9 uses) and `SurfaceRefresherTests.swift` (10 uses), replace `turnWillBegin()` with `submissionWillBegin()`. In `MCPSessionSweepTests.swift`, change the `cancelCurrentTurn()` reference to `cancel()`.
- [x] `submissionWillBegin()` now also runs between continuation submissions of one answer (compaction yield, rejected tool call, repetition recovery). So a staged registry can be applied in the middle of an answer. Add a test for this.
- [x] Fix each other compile error or test failure that `swift build --build-tests && swift test` reports against Router `c208add`. Record the list in a task comment.

## Acceptance Criteria
- [x] `swift build --build-tests` passes with no errors and no new warnings.
- [x] `swift test` passes.
- [x] `rg -w 'turnWillBegin|TurnBoundaryTool|cancelCurrentTurn' Tests` returns no match.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/RegistrySwapTests.swift`: stage a registry that removes a verb, call `submissionWillBegin()` between two calls of one answer, and check that a later `runCode` call to the removed verb gives a repairable tool error (the unknown-verb hint), not a crash.
- [x] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.