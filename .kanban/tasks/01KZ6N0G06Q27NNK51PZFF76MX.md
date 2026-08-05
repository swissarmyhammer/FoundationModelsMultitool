---
assignees:
- claude-code
depends_on:
- 01KZ6MYJSSSF41HXMC2YAHBKG5
position_column: todo
position_ordinal: '8580'
title: '[MultiTool] Remove the blocking bridge; tools.* return promises'
---
Repo: this repo. Basis: eventplan.md §"Async JavaScript". Depends on the interpreter promise pump.

## What
Delete the v1 blocking bridge in `Sources/FoundationModelsMultitool/MultiTool.swift` and re-glue `tools.*` onto the async pump:
- Remove `performInvocation`'s `DispatchSemaphore` + `OSAllocatedUnfairLock` machinery and `invokeBlocking` (MultiTool.swift:580-620); each `tools.*` entry becomes an async host function whose body is `ToolInvoker.invoke(tool, content:)` + `ArgumentMarshaler.renderOutput` running in a Swift `Task`. Update the doc comment block at MultiTool.swift:467-522 that documents the semaphore design.
- Error mapping unchanged in substance: a rejected promise surfaces as a JS exception at the `await` point carrying the same repairable message (`ToolInvokerError`/`ArgumentMarshalerError` text survives verbatim — pinned by ResultRendererTests); tool-thrown errors still propagate unwrapped.
- `Rendering/ResultRenderer.swift` / `MultiTool.run`: the final value awaits a thenable (`return tools.x.y(...)` without `await` is correct); settle-before-return applies at the snippet boundary (pump provides it — verify end-to-end here).
- Keep `help()`/`docs()` synchronous host functions; console capping and `MultiToolConfiguration.resultLimits` unchanged.
- Update `MultiTool.description` (MultiTool.swift:160-174) with the one async line the plan specifies: await each `tools.*` call; use `Promise.all` to run calls in parallel. (`MultiToolExecutionTests` line 88 pins the description — update the pin.)

## Acceptance Criteria
- [ ] No `DispatchSemaphore` remains in Sources/
- [ ] A snippet with `Promise.all` over two slow fixture tools completes in ~max, not ~sum, of their durations (use `DelayedTool`-style fixtures from `Tests/.../Fixtures/MultiToolExecutionFixtures.swift`)
- [ ] A validation failure inside an awaited call rejects with the identical `ToolInvokerError` message text v1 produced
- [ ] Task cancellation of a running snippet still cancels within the watchdog window
- [ ] Full `swift test` green

## Tests
- [ ] Update/extend `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: awaited call happy path; parallel `Promise.all` concurrency; unawaited-return correctness; floating-call settle-before-return; rejection message parity; description pin update
- [ ] `swift test` green (all suites)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1