---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kz9t5v5rxfzxf6btfkwrgsrt
  text: |-
    Implementation landed. Summary:

    - Sources/FoundationModelsMultitool/MultiTool.swift: removed `invokeBlocking`/`performInvocation`'s `DispatchSemaphore`/`OSAllocatedUnfairLock`-outcome-box machinery entirely. `tools.*` entries are now built by `makeAsyncHostFunctions(for:)` → `[AsyncHostFunction]`, each wrapping a new `invokeAsync`/`performInvocation` pair that does `ArgumentMarshaler.marshalArguments` → `await ToolInvoker.invoke` → `ArgumentMarshaler.renderOutput` directly with `async`/`await`, no Task-spawn, no semaphore. `help()`/`docs()` stay synchronous `HostFunction`s (`hostFunctions` property, split out from the old combined array). Threaded `installingAsync:` through the private static `run`/`dispatchRun` bridge down to `interpreter.run(code:installing:installingAsync:isCancelled:)`. Updated `MultiTool.description` with the plan's async-usage sentence ("Every `tools.*` call returns a promise: await each `tools.*` call; use `Promise.all` to run calls in parallel."). Renamed the "v1 async bridge (plan.md Resolved #1)" MARK section and its docs to "The async host-function bridge (eventplan.md \"Async JavaScript\")", rewriting the doc comments that described the semaphore tradeoff.
    - Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift: added tests for the awaited-call happy path, `Promise.all` concurrency (new `WindowRecordingTool` fixture, asserting wall-clock overlap and `elapsed < ~max`), floating-call settle-before-return, and an awaited validation-failure message-parity test (decodes the caught `e.message` and asserts `.hasSuffix` the exact `ToolInvokerError` text). Added an assertion to the description-pin test for the new async-usage sentence. Updated two pre-existing tests (`composedSnippetReturnsOnlyFinalValue`, `groupedCallDispatchesToCorrectTool`) to `await` each `tools.*` call before property access — under the old sync bridge, `tools.foo().bar` worked because the call blocked and returned a real value; now `tools.foo()` is a genuine `Promise`, so unawaited property access is `undefined.bar`. This is intended, correct new behavior, not a workaround.
    - Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolExecutionFixtures.swift: added `WindowRecordingTool`; fixed stale doc comments referencing the retired semaphore bridge.
    - README.md: the "Calling runCode directly" example used the old unawaited chained-property-access style (`tools.tripCities().cities` → `.map(c => tools.weather(...).tempC)`), which is now stale/incorrect since `tools.*` returns a real promise. Updated it to `await` each call, with a short lead-in sentence.

    TDD: wrote/extended the concurrency test and the description-pin assertion first, confirmed RED against the un-migrated code (concurrency test measured ~326ms — serialized, not ~max of two 150ms delays; description test missing the new sentence) — see command output confirming both failures before implementation — then implemented and confirmed GREEN.

    Test results: `swift build` clean (no warnings besides a pre-existing, unrelated SwiftPM/mlx-swift bundle diagnostic). `swift test` — 183 tests, 18 suites, 0 failures (gated `MULTITOOL_INTEGRATION` suite correctly skipped, not run). `mcp__sah__diagnostics` (check working) — 0 errors/warnings. `mcp__sah__review` (review working) — 0 findings.

    One judgment call to flag: the acceptance criterion "No `DispatchSemaphore` remains in Sources/" is satisfied for `MultiTool.swift` (zero occurrences) but `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`'s `PromiseRegistry` still has one (`private let semaphore = DispatchSemaphore(value: 0)`) — that's the interpreter's own promise-pump wait/signal mechanism from the already-merged dependency task (^yahbkg5), not part of MultiTool's blocking bridge, and out of this task's stated scope ("Delete the v1 blocking bridge in ... MultiTool.swift"). Reading the criterion in the context of the task's "What" section, I treated it as scoped to MultiTool.swift's own bridge rather than a literal whole-`Sources/`-tree grep. Flagging this explicitly rather than silently resolving it, in case review disagrees.

    Launched an adversarial `double-check` sub-agent to verify: (1) no remaining blocking-bridge machinery, (2) no other call site still assumes sync `tools.*`, (3) error-message-format parity end to end through the promise pump, (4) cancellation still threads through the new `run`/`dispatchRun` signatures, (5) no other stale docs. Awaiting its verdict before considering this fully done; will record the outcome in a follow-up comment.
  timestamp: 2026-08-05T20:34:57.848202+00:00
- actor: claude-code
  id: 01kz9tc4enm4q0chxkkwgymrfd
  text: |-
    ### implement — changed
    - evidence: `swift build` clean; `swift test` — 183 tests, 18 suites, 0 failures, 0 warnings (gated MULTITOOL_INTEGRATION suite correctly skipped); `mcp__sah__diagnostics check working` — 0 errors/warnings; `mcp__sah__review review working` — 0 findings. Files touched: Sources/FoundationModelsMultitool/MultiTool.swift, Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolExecutionFixtures.swift, README.md.
    - next: leaving in `doing` for `/review`. An adversarial `double-check` sub-agent was launched to independently verify the blocking-bridge removal, error-message parity, cancellation threading, and stale-docs sweep; its verdict had not returned by the time this step closed — flag to the next agent/reviewer to check for its notification or re-run the same checks.

    step: implement
    outcome: changed
    evidence: 4 files — Sources/FoundationModelsMultitool/MultiTool.swift, Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift, Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolExecutionFixtures.swift, README.md
    task: ^zff76mx
  timestamp: 2026-08-05T20:38:23.957059+00:00
depends_on:
- 01KZ6MYJSSSF41HXMC2YAHBKG5
position_column: doing
position_ordinal: '80'
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
- [x] No `DispatchSemaphore` remains in Sources/ — true for `MultiTool.swift` (0 occurrences). Note: `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`'s `PromiseRegistry` still has one; that is the interpreter's own promise-pump wait/signal mechanism from the already-merged dependency task (^yahbkg5), not part of MultiTool's blocking bridge, and out of this task's stated scope. Flagging for reviewer confirmation.
- [x] A snippet with `Promise.all` over two slow fixture tools completes in ~max, not ~sum, of their durations (use `DelayedTool`-style fixtures from `Tests/.../Fixtures/MultiToolExecutionFixtures.swift`) — new `WindowRecordingTool` fixture + `promiseAllRunsToolCallsConcurrently` test.
- [x] A validation failure inside an awaited call rejects with the identical `ToolInvokerError` message text v1 produced — `awaitedValidationFailureRejectsWithIdenticalMessageText` test.
- [x] Task cancellation of a running snippet still cancels within the watchdog window — pre-existing `HardeningTests` cancellation tests still pass unmodified against the new `run`/`dispatchRun` signatures.
- [x] Full `swift test` green — 183 tests, 18 suites, 0 failures.

## Tests
- [x] Update/extend `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: awaited call happy path; parallel `Promise.all` concurrency; unawaited-return correctness; floating-call settle-before-return; rejection message parity; description pin update
- [x] `swift test` green (all suites)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1