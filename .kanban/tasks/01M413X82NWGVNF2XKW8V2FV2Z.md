---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m415tzs67y76p95rav4hw3we
  text: |-
    Research done. Discoveries:
    - Two more test files call `JSCInterpreter(timeLimit:watchdogClock:)`. The card does not list them: `MetricsTests.timedOutRunRecordsTimedOut` and `TypedMockDryRunTests.nonTerminatingSnippetFails`. Both call the interpreter directly and test only the sandbox clock. `TypedMockDryRun` has one production caller, `SampleSnippet` (searchTools). The user decided that searchTools has no timeout. Thus I delete these two tests too, by the user decision "Delete tests that test only the removed clocks". Then eight files change, not six.
    - `makeWithHeldWatchdog(timeLimit:)` has no caller that gives `timeLimit`. When the helper returns `JSCInterpreter()`, the parameter and `heldWatchdogTimeLimit` are dead. I remove both, so that the dead-code rule passes. The callers do not change.
    - `docs/SECURITY.md` (section on the snippet ceiling) names `JSCInterpreter(timeLimit:)` and the wall-clock timer of the run. That text is also about the `MultiTool.init` re-arm, which `^ydnnjs`-scope task 01M413YDNNJSNTFCJEY71CBG70 removes. No card owns that doc. I add a new task for it.
  timestamp: 2026-10-03T15:24:04.262245+00:00
- actor: claude-code
  id: 01m416b44fcppjcqpjx362tb80
  text: |-
    Implementation landed.
    - Correction to the research comment: the task that removes `withTimeLimit` and the re-arm is `^71cbg70` (01M413YDNNJSNTFCJEY71CBG70). The helper task is `^tt2rg2x`. The text "^ydnnjs" in the research comment is wrong.
    - TDD: RED was the new test `JSCInterpreterTests.withTimeLimitReturnsTheReceiver` (it failed: the old `withTimeLimit` gave a new instance). GREEN after the change. Task `^71cbg70` removes that test with the requirement.
    - `WatchdogState` now records only a cancellation (a lock on a `Bool`, `isCancellationRecorded`/`recordCancellation()`). The enum `Cause` is gone. `outcome(of:)` lost its `timeLimit` parameter.
    - Eight files changed, not six. `MetricsTests.timedOutRunRecordsTimedOut` and `TypedMockDryRunTests.nonTerminatingSnippetFails` used the removed init and tested only the sandbox clock, thus I deleted them (user decision). `makeWithHeldWatchdog()` lost its unused `timeLimit` parameter and `heldWatchdogTimeLimit`.
    - I also corrected stale comments that the change made false: the suite doc of `HardeningTests`, the doc of `cancellationForcesEarlyTerminationOfAnInfiniteLoop`, and the comment in `syntaxCheckExecutesNothing`.
    - New task `^1rymb3e` (01M416A0E4QXZKCTE4M1RYMB3E) updates `docs/SECURITY.md`, which still names `JSCInterpreter(timeLimit:)` and the wall-clock timer of the run.
    - The build prints one warning that is not from this code: "missing creator for mutated node: ... mlx-swift_Cmlx.bundle". It comes from the build system for the mlx-swift dependency.
  timestamp: 2026-10-03T15:32:53.007295+00:00
- actor: claude-code
  id: 01m416b9tr956c6h1mwy17s5rm
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift, Sources/FoundationModelsMultitool/Discovery/SampleSnippet.swift, Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift, Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift, Tests/FoundationModelsMultitoolTests/HardeningTests.swift, Tests/FoundationModelsMultitoolTests/MetricsTests.swift, Tests/FoundationModelsMultitoolTests/TypedMockDryRunTests.swift. RED: `swift test --filter 'JSCInterpreterTests/withTimeLimitReturnsTheReceiver'` 1 test, 1 failure. GREEN: `swift test --filter 'JSCInterpreterTests|HardeningTests|SampleSnippetTests|SearchToolsToolTests|RunCodeToolTimeoutTests|MetricsTests|TypedMockDryRunTests'` 132 tests in 7 suites passed. `swift test`: 1890 tests in 156 suites passed, 0 failures. `rg "WatchdogDeadline|wallClockExpired|watchdogClock|defaultCheckTimeLimit" Sources Tests` finds nothing.
    - next: /review. Follow-up task ^1rymb3e for docs/SECURITY.md.
  timestamp: 2026-10-03T15:32:58.840602+00:00
- actor: claude-code
  id: 01m416bj5gbdpfwndpn2tna91m
  text: 'Correction to the two comments above: seven code files changed, not eight. The card lists five files (it says "six"), and this work added two (`MetricsTests.swift`, `TypedMockDryRunTests.swift`). The file list in the step record is complete.'
  timestamp: 2026-10-03T15:33:07.376024+00:00
depends_on:
- 01M413WCH2DEDEQ4DNYE2XVHTK
position_column: doing
position_ordinal: '80'
title: Remove the deadline and the wall-clock timer from JSCInterpreter
---
## What
Rule: each call path has one outer, tool-level timeout. The JSC sandbox has its own clock with the same value as the `runCode` engine timeout. The two clocks race and give different outcomes: when the engine fires, the outcome is `.timedOut`, and when JSC fires, it is `.succeeded` with the text "The snippet timed out…". Remove the sandbox clock. `searchTools` (SampleSnippet) must have no timeout, by decision of the user: it is simple and runs in process.

In `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`:
- [x] Remove `WatchdogDeadline`, the `onDeadline`/`wallClockExpired()` timer job, the stored `timeLimit` and `watchdogClock`, and the `init(timeLimit:watchdogClock:)` / `init(timeLimit:)` parameters. Keep a plain `JSCInterpreter()` init.
- [x] Keep the CPU watchdog (`WatchdogState`, `jscTerminateCallback`, `watchdogPollInterval`, the self re-arm). It must check only `isCancelled`. Remove `Cause.timedOut` and the `InterpreterError(kind: .timeout)` path. A cancelled task (from the engine timeout) still stops `while (true) {}` at the next 20 ms poll, and still ends a run that waits.
- [x] Make `withTimeLimit(_:)` return `self` for now. The protocol doc in `Interpreter.swift` allows this for a conformer with no wall-clock mechanism. A later task removes the requirement.
- [x] Update the type doc ("Two clocks bound a run…") to say that cancellation is the only stop.

Other files:
- [x] `Sources/FoundationModelsMultitool/Discovery/SampleSnippet.swift`: remove `SampleSnippetConfig.defaultCheckTimeLimit`. The default `interpreter:` becomes `JSCInterpreter()`. Update the doc comment.
- [x] `Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift`: make `makeWithHeldWatchdog()` return `JSCInterpreter()` so the callers still compile. A later task removes the helper.
- [x] `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift`: remove `infiniteLoopTerminatedByWatchdog`, `withTimeLimitReturnsAnInterpreterArmedWithTheGivenLimit`, `wallClockLimitEndsARunThatWaitsForever`. Keep the cancellation tests (`cancellationForcesEarlyTerminationOfAnInfiniteLoop`, `cancellationCancelsPendingAsyncHostFunction`, …).
- [x] `Tests/FoundationModelsMultitoolTests/HardeningTests.swift`: remove `executionTimeLimitBoundaryTerminatesNearConfiguredLimit`, `executionTimeLimitBoundaryAllowsAFastSnippet`, `executionTimeLimitBelowAnInjectedInterpretersOwnLimitIsEnforced`, `executionTimeLimitAboveAnInjectedInterpretersOwnLimitIsEnforced` and their helpers. Task `^e2xvhtk` covers this behavior at the tool level.

Six files change. The edits in the test helper and SampleSnippet are one line each.

## Acceptance Criteria
- [x] `rg "WatchdogDeadline|wallClockExpired|watchdogClock|defaultCheckTimeLimit" Sources Tests` finds nothing.
- [x] `InterpreterError.Kind.timeout` has no producer in `JSCInterpreter.swift`.
- [x] A cancelled run of `while (true) {}` still throws `CancellationError`.
- [x] The tool-level timeout tests from `^e2xvhtk` pass.

## Tests
- [x] Keep and run the cancellation tests in `JSCInterpreterTests.swift`.
- [x] `swift test --filter JSCInterpreterTests`, `--filter HardeningTests`, `--filter SampleSnippetTests`, `--filter SearchToolsToolTests` pass. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt