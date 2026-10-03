---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m414sr1rhnq3gs39j9p2ttmc
  text: |-
    Research:
    - The engine clock in `ToolRun.resultOrTimeout` / `RunEventFunnel.waitForTimeout` uses `Task.sleep` on real time. It is not injectable. Thus the tests use a small `executionTimeLimit` and wait for the real window. No test reads the time.
    - At the timeout, the engine cancels the call. The terminal event has outcome `.timedOut` and detail `ToolMountError.timedOut(tool:timeoutSeconds:).description` ("runCode timed out after N seconds with no progress").
    - `SuspendedContextTests` has the mount pattern (`run.context.mount(_:as:postingTo:)`) and `GatedTool` + `ToolReleaseLatch` for a `tools.*` call that never completes. `context.wait(completionToken:seconds:)` gives the terminal event also when the run settled inside `inlineSettleGrace`.
    - Progress test plan: the snippet calls `progress()` and then awaits a short `WindowRecordingTool` sleep, many times. The sum of the sleeps is more than one window (a sleep is a minimum, so this is a lower bound and not a measurement). Each gap is much less than the window. Without the reset, the engine ends the run at the first window.
    - Plan: new file `Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift`.
  timestamp: 2026-10-03T15:05:55.000740+00:00
- actor: claude-code
  id: 01m4159fspvqj442b17tc87y5c
  text: |-
    Implementation:
    - New file `Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift`, suite "runCode ends at its tool-level timeout", with three tests. Each test mounts `MultiTool` with `context.mount(_, as: .synchronous)`, a small `executionTimeLimit`, and `JSCInterpreter.makeWithHeldWatchdog()`. Each test reads the terminal event from the run plane with the shared `TerminalDetail.settledEvent(of:in:)`. No test calls `multiTool.call(arguments:)`. No library code changed.
    - Test 1: `while (true) {}` ends `.timedOut` with `ToolMountError.timedOut(tool: "runCode", timeoutSeconds: 0.3).description`.
    - Test 2: `await tools.gated()` (a `GatedTool` that nothing releases) ends the same way. The test also sees that the timeout cancelled the pending call (`gated.wasCancelled`).
    - Test 3: a 2 s window. The snippet calls `progress()` and then awaits a pause of 0.2 s, 20 times (4 s, a lower bound because a sleep is a minimum). It ends `.succeeded` with `"pause-result"`.
    - RED check: with the `progress()` line removed, test 3 failed with `.timedOut` and "runCode timed out after 2.0 seconds with no progress". Thus completed `tools.*` calls do not reset the clock, and only `progress()` does. Tests 1 and 2 passed in that same run.
    - Evidence: `swift test --filter RunCodeToolTimeout` 3 of 3 passed, no warnings. `swift test` 1898 tests in 156 suites passed.
    - All the checkboxes on the card are done.
  timestamp: 2026-10-03T15:14:30.838663+00:00
- actor: claude-code
  id: 01m4159hp319s72sazg9jfn23p
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift (new); `swift test --filter RunCodeToolTimeout` 3/3 passed; `swift test` 1898 tests in 156 suites passed, 0 warnings
    - next: /review (the task stays in doing)
  timestamp: 2026-10-03T15:14:32.771319+00:00
position_column: doing
position_ordinal: '80'
title: Test the runCode timeout at the tool level (engine), not in the sandbox
---
## What
Rule: each call path has one outer, tool-level timeout. For `runCode`, this is the engine clock that `MultiTool.timeout(from:)` gives (`Sources/FoundationModelsMultitool/MultiTool+Background.swift:133`). The engine enforces it in `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/Hosting/ToolRun.swift` (`resultOrTimeout`, `waitForTimeout`). A progress event resets this clock. This is correct, because progress shows real activity.

Today, the timeout tests in `Tests/FoundationModelsMultitoolTests/HardeningTests.swift` call `multiTool.call(arguments:)` directly. They test only the JSC sandbox deadline. Thus they do not prove the tool-level timeout. Later tasks remove the JSC deadline. Before that, this task adds tests that prove the tool-level timeout through the session mount.

Approach:
- Mount `MultiTool` the way a Router session does: `context.mount(tool, as: .synchronous)`. See `mounted(_:on:)` in `Tests/FoundationModelsMultitoolTests/InlineSettleGraceTests.swift` for the pattern.
- Use a small `MultiToolConfiguration(executionTimeLimit:)`.
- Inject `JSCInterpreter.makeWithHeldWatchdog()` (`Tests/FoundationModelsMultitoolTests/Support/JSCInterpreter+HeldWatchdog.swift`) as the interpreter, so that the sandbox clock cannot fire. Then only the engine clock can end the run, and the test is deterministic now and after the JSC deadline is removed.
- Read the terminal outcome from the run plane or the session mail, as the existing mount tests do.

## Acceptance Criteria
- [x] A mounted `runCode` with `while (true) {}` ends with the engine terminal outcome `.timedOut` and the `ToolMountError.timedOut` text ("runCode timed out after … with no progress").
- [x] A mounted `runCode` that awaits a `tools.*` call that never completes ends with `.timedOut` the same way.
- [x] A mounted `runCode` that calls `progress()` before the window ends is not ended at the first window. This proves that progress resets the clock.
- [x] No new test calls `multiTool.call(arguments:)` directly to test a timeout.

## Tests
- [x] Add three tests to `Tests/FoundationModelsMultitoolTests/HardeningTests.swift` (or a new `Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift`) for the three criteria above.
- [x] No test measures the speed of the machine. Use the existing test clocks and `TestPoll` only as a hang bound.
- [x] `swift test --filter RunCodeToolTimeout` (or `HardeningTests`) passes. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #tech-debt #timeouts