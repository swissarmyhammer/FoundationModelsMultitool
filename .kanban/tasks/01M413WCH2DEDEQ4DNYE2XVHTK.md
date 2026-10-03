---
assignees:
- claude-code
position_column: todo
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
- [ ] A mounted `runCode` with `while (true) {}` ends with the engine terminal outcome `.timedOut` and the `ToolMountError.timedOut` text ("runCode timed out after … with no progress").
- [ ] A mounted `runCode` that awaits a `tools.*` call that never completes ends with `.timedOut` the same way.
- [ ] A mounted `runCode` that calls `progress()` before the window ends is not ended at the first window. This proves that progress resets the clock.
- [ ] No new test calls `multiTool.call(arguments:)` directly to test a timeout.

## Tests
- [ ] Add three tests to `Tests/FoundationModelsMultitoolTests/HardeningTests.swift` (or a new `Tests/FoundationModelsMultitoolTests/RunCodeToolTimeoutTests.swift`) for the three criteria above.
- [ ] No test measures the speed of the machine. Use the existing test clocks and `TestPoll` only as a hang bound.
- [ ] `swift test --filter RunCodeToolTimeout` (or `HardeningTests`) passes. `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt