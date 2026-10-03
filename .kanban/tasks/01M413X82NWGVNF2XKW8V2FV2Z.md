---
assignees:
- claude-code
depends_on:
- 01M413WCH2DEDEQ4DNYE2XVHTK
position_column: todo
position_ordinal: '8180'
title: Remove the deadline and the wall-clock timer from JSCInterpreter
---
## What
Rule: each call path has one outer, tool-level timeout. The JSC sandbox has its own clock with the same value as the `runCode` engine timeout. The two clocks race and give different outcomes: when the engine fires, the outcome is `.timedOut`, and when JSC fires, it is `.succeeded` with the text "The snippet timed out…". Remove the sandbox clock. `searchTools` (SampleSnippet) must have no timeout, by decision of the user: it is simple and runs in process.

In `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`:
- [ ] Remove `WatchdogDeadline`, the `onDeadline`/`wallClockExpired()` timer job, the stored `timeLimit` and `watchdogClock`, and the `init(timeLimit:watchdogClock:)` / `init(timeLimit:)` parameters. Keep a plain `JSCInterpreter()` init.
- [ ] Keep the CPU watchdog (`WatchdogState`, `jscTerminateCallback`, `watchdogPollInterval`, the self re-arm). It must check only `isCancelled`. Remove `Cause.timedOut` and the `InterpreterError(kind: .timeout)` path. A cancelled task (from the engine timeout) still stops `while (true) {}` at the next 20 ms poll, and still ends a run that waits.
- [ ] Make `withTimeLimit(_:)` return `self` for now. The protocol doc in `Interpreter.swift` allows this for a conformer with no wall-clock mechanism. A later task removes the requirement.
- [ ] Update the type doc ("Two clocks bound a run…") to say that cancellation is the only stop.

Other files:
- [ ] `Sources/FoundationModelsMultitool/Discovery/SampleSnippet.swift`: remove `SampleSnippetConfig.defaultCheckTimeLimit`. The default `interpreter:` becomes `JSCInterpreter()`. Update the doc comment.
- [ ] `Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift`: make `makeWithHeldWatchdog()` return `JSCInterpreter()` so the callers still compile. A later task removes the helper.
- [ ] `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift`: remove `infiniteLoopTerminatedByWatchdog`, `withTimeLimitReturnsAnInterpreterArmedWithTheGivenLimit`, `wallClockLimitEndsARunThatWaitsForever`. Keep the cancellation tests (`cancellationForcesEarlyTerminationOfAnInfiniteLoop`, `cancellationCancelsPendingAsyncHostFunction`, …).
- [ ] `Tests/FoundationModelsMultitoolTests/HardeningTests.swift`: remove `executionTimeLimitBoundaryTerminatesNearConfiguredLimit`, `executionTimeLimitBoundaryAllowsAFastSnippet`, `executionTimeLimitBelowAnInjectedInterpretersOwnLimitIsEnforced`, `executionTimeLimitAboveAnInjectedInterpretersOwnLimitIsEnforced` and their helpers. Task `^e2xvhtk` covers this behavior at the tool level.

Six files change. The edits in the test helper and SampleSnippet are one line each.

## Acceptance Criteria
- [ ] `rg "WatchdogDeadline|wallClockExpired|watchdogClock|defaultCheckTimeLimit" Sources Tests` finds nothing.
- [ ] `InterpreterError.Kind.timeout` has no producer in `JSCInterpreter.swift`.
- [ ] A cancelled run of `while (true) {}` still throws `CancellationError`.
- [ ] The tool-level timeout tests from `^e2xvhtk` pass.

## Tests
- [ ] Keep and run the cancellation tests in `JSCInterpreterTests.swift`.
- [ ] `swift test --filter JSCInterpreterTests`, `--filter HardeningTests`, `--filter SampleSnippetTests`, `--filter SearchToolsToolTests` pass. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt