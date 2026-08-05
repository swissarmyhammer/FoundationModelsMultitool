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
- actor: claude-code
  id: 01kz9tphrf3c5cqmw4txq6j7er
  text: |-
    Adversarial `double-check` sub-agent returned. Verdict: REVISE, 5 findings. Addressed each:

    1. **AC1 conflict** ("No `DispatchSemaphore` remains in Sources/" vs. `JSCInterpreter.swift`'s `PromiseRegistry` semaphore, from the already-merged dependency task ^yahbkg5). The double-check correctly called out that my earlier comment self-released this criterion via my own judgment, which the rules don't permit. Retracted that framing; recorded it as an explicit, unresolved `## Blocker` on the task description instead, and unchecked the box. Did **not** remove or alter `JSCInterpreter.swift`'s semaphore — it is that already-reviewed task's own internal promise-pump synchronization primitive, not part of MultiTool's blocking bridge, and touching it is outside this task's stated scope and would require redesigning the promise pump. A human needs to confirm/amend the criterion's intended scope.

    2. **ToolAPIRenderer still declares synchronous return types and unawaited `@example`s** for every `tools.*` binding — real defect, contradicts the new async contract, but touches a different subsystem (Surface/ToolAPIRenderer.swift, Discovery, goldens) not named in this task's "What" section. Filed as new task ^aspycka ("[ToolAPIRenderer] Render tools.* declared return types as Promise<T>, and await examples"), depends on this task.

    3. **No MultiTool-level cancellation test covered the new pump-wait path** (cancelling while parked in `pumpUntilSettled` awaiting a pending `tools.*` promise, as opposed to the pre-existing `while(true){}` watchdog-timeout path). This was a real, in-scope gap against this task's own acceptance criterion 4. Fixed directly: added `cancellationCancelsWhileAwaitingAPendingToolCall` to `Tests/FoundationModelsMultitoolTests/HardeningTests.swift`, using a `WindowRecordingTool` with a 5s delay; cancels after 100ms and asserts `CancellationError` within 3s. Ran and confirmed it passes (0.116s), which is only possible if cancellation actually interrupted the pending 5s tool call rather than waiting it out.

    4. **Message-parity claim not exactly true in one branch** — `JSCInterpreter.swift`'s async `settle(_:in:)` success-branch JSON-conversion-failure path hardcodes `"<name>: could not convert the result to JSON."` instead of interpolating the real underlying error the way the sync bridge's uniform catch-and-interpolate does. This is inside `JSCInterpreter.swift` (not touched by this task's diff, and part of the already-merged ^yahbkg5 deliverable) and the path is close to unreachable in practice (every `InterpreterValue` is already JSON-safe by construction). Filed as new task ^ws38ajz, depends on this task. Corrected the wording of acceptance criterion 3 on this card to note the scoped, pinned parity (thrown-error path) rather than an unqualified "identical" claim.

    5. **Unrelated uncommitted `eventplan.md` diff sits in the working tree** — confirmed this predates my session (it was already listed as modified in the very first `git status` I ran, before I touched anything; per project memory, other sessions temp-swap files in this tree). Not something I created, and I am not committing per this task's own instructions — flagging here so whoever does commit stages explicitly (`MultiTool.swift`, the two test files, `README.md`) rather than `git commit -a`.

    Re-ran the full suite after fix #3: `swift test` — 184 tests, 18 suites, 0 failures, 0 real warnings. `swift build` clean.

    ### implement — changed
    - evidence: `swift test` — 184 tests, 18 suites, 0 failures. Added `Tests/FoundationModelsMultitoolTests/HardeningTests.swift::cancellationCancelsWhileAwaitingAPendingToolCall`. Filed follow-up tasks ^aspycka and ^ws38ajz. Recorded an unresolved blocker on acceptance criterion 1 (DispatchSemaphore scope) rather than self-releasing it.
    - next: leaving in `doing`. This task is NOT fully done — AC1 has an open, human-adjudication-required blocker. Everything else (implementation, all other acceptance criteria, all tests) is complete and green.

    step: implement
    outcome: stuck
    evidence: AC1 ("No DispatchSemaphore remains in Sources/") conflicts with the already-merged JSCInterpreter.swift PromiseRegistry semaphore from dependency task ^yahbkg5; recorded as `## Blocker` on this task's description, not resolved. All other acceptance criteria and tests are green (184 tests, 18 suites, 0 failures).
    task: ^zff76mx
  timestamp: 2026-08-05T20:44:05.263707+00:00
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
- [ ] No `DispatchSemaphore` remains in Sources/ — **BLOCKED, unresolved conflict, see `## Blocker` below.** True for `MultiTool.swift` itself (0 occurrences after this change), but `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`'s `PromiseRegistry` still has one. A prior self-review comment on this task claimed this was out of scope and released the criterion — that was improper (own judgment does not release a criterion) and is retracted here. Recorded as a blocker, not resolved; a human must decide whether this criterion is scoped to `MultiTool.swift` or the whole `Sources/` tree.
- [x] A snippet with `Promise.all` over two slow fixture tools completes in ~max, not ~sum, of their durations (use `DelayedTool`-style fixtures from `Tests/.../Fixtures/MultiToolExecutionFixtures.swift`) — new `WindowRecordingTool` fixture + `promiseAllRunsToolCallsConcurrently` test.
- [x] A validation failure inside an awaited call rejects with the identical `ToolInvokerError` message text v1 produced — `awaitedValidationFailureRejectsWithIdenticalMessageText` test. (Parity holds for the thrown-error path pinned by this test; an adversarial review found one narrow, separate divergence in a different, close-to-unreachable failure mode — filed as ^ws38ajz.)
- [x] Task cancellation of a running snippet still cancels within the watchdog window — pre-existing `HardeningTests` cancellation tests pass unmodified against the new `run`/`dispatchRun` signatures, **and** a new `cancellationCancelsWhileAwaitingAPendingToolCall` test now covers the new pump-wait path specifically (cancelling while parked in `pumpUntilSettled` awaiting a pending `tools.*` promise, not just the watchdog-timeout `while(true){}` path) — this gap was found by an adversarial double-check review and fixed.
- [x] Full `swift test` green — 184 tests, 18 suites, 0 failures.

## Tests
- [x] Update/extend `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift`: awaited call happy path; parallel `Promise.all` concurrency; unawaited-return correctness; floating-call settle-before-return; rejection message parity; description pin update
- [x] `swift test` green (all suites)

## Blocker
Acceptance criterion "No `DispatchSemaphore` remains in Sources/" conflicts with already-merged code: `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`'s `PromiseRegistry.semaphore` (`private let semaphore = DispatchSemaphore(value: 0)`), the interpreter's own promise-pump wait/signal mechanism, landed in the dependency task ^yahbkg5 and is structurally required by that design (it is how `waitAndTakeReadyToSettle` blocks the interpreter's worker thread until an async host function's `Task` reports completion — removing it would mean redesigning the already-reviewed promise pump, which is outside this task's "What" section). I believe the criterion's evident intent, read against the task's own "What" section and eventplan.md's "Async JavaScript" rationale ("We do not build a semaphore-based park mechanism... only to delete them later" — describing the *rejected* alternative, not the promise pump's own retained internal one), is scoped to `MultiTool.swift`'s v1 blocking bridge specifically. But per the review-findings rule, my own judgment does not get to release this — a human should confirm or amend the criterion's scope.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1