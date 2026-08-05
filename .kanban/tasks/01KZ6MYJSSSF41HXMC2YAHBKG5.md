---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kz8shrnna3yxyp2xdzmetx7n
  text: |-
    Picked up. Research + throwaway platform probe (scratchpad, deleted after) pinned the mechanism before any code:

    1. `JSValue(newPromiseIn:fromExecutor:)` calls its executor synchronously, so the bridge can capture `resolve`/`reject` while still inside the host-function call and return the promise to the snippet.
    2. Calling `resolve.call(...)`/`reject.call(...)` from Swift *after* `evaluateScript` has returned resumes the async IIFE and drains the microtask queue synchronously — the outer `outcome.done` flips during that same call. So a pump loop that settles promises one at a time on the JS thread is sufficient; no run loop needed.
    3. `JSGlobalContextSetUnhandledRejectionCallback` is present in the OS-27 SDK's `JavaScriptCore.tbd` (checked the same way the watchdog symbols were pinned) and links via `@_silgen_name`. Measured semantics: it fires for a *floating* rejected host promise and does NOT fire when the snippet handles the rejection with `try/catch` or `.catch(...)`. That is the only way to satisfy "a floating rejection fails the run" without breaking `try { await tools.x() } catch (e) { ... }`, which a naive "any rejection fails the run" rule would wrongly fail.
    4. `return hostCall();` (no `await`) is already correct without extra work: an async function's return value adopts a thenable, so `outcome.value` is the settled value by the time the wrapper's `.then` runs. Needs a test, not a mechanism.

    Deadlock note for the next agent: `run` is synchronous and holds the interpreter's serial queue via `queue.sync`, so a settling Swift `Task` must NOT hop back with `queue.async` — it would deadlock. Settlements are handed over as Sendable data through a semaphore mailbox that the JS thread drains in place.

    Also: while the pump waits, no JS is executing, so JSC's own watchdog callback cannot fire. `WatchdogState` needs a poll entry point the pump loop calls itself.
  timestamp: 2026-08-05T11:04:45.493551+00:00
- actor: claude-code
  id: 01kz9jdyx0hvxq65q95srdqfrx
  text: |-
    Picked up an already-substantial in-progress diff (Interpreter.swift, JSCInterpreter.swift, JSCInterpreterTests.swift) from an earlier, apparently interrupted session. Read it in full rather than restarting: `AsyncHostFunction` shape, the `PromiseRegistry`/`pumpUntilSettled` promise-pump machinery, the thenable-wrapper trick for observing `.then`/`.catch`/`.finally`/`await` uniformly, and 20 new JSCInterpreterTests cases were already implemented and internally well-documented. Did not rewrite or restart — verified it against the task's Acceptance Criteria/Tests lists and ran it.

    Ran `swift build` (clean, no new warnings), `swift test --filter JSCInterpreter` (32/32 green), full `swift test` (176/176 green + 6 gated-integration tests correctly skipped without `MULTITOOL_INTEGRATION`), `mcp__sah__diagnostics check working` (0 errors/warnings), and `mcp__sah__review review working` (0 findings). Made no code changes — the prior session's implementation was already complete and correct; my contribution this pass was verification plus updating the task description's checkboxes to reflect the now-confirmed-passing state.

    One documented deviation worth flagging explicitly (already justified in code comments, but the code's comment references "recorded on task 01KZ6MYJSSSF41HXMC2YAHBKG5" which hadn't actually happened yet — recording it now to close that loop): the AC/eventplan.md wording "reject each pending promise" on cancellation/timeout is narrowed in the implementation. `pumpUntilSettled`/`PromiseRegistry.cancelAllPending` never call `resolve`/`reject` on a pending promise when the watchdog decides to terminate — they cancel the backing Swift `Task` and leave the JS promise permanently pending, then tear the sandbox down immediately. Rationale (per the code's own doc comments): settling a promise resumes JS execution (drains the microtask queue, runs any `.then`/`.catch`) *outside* the watchdog's own re-armed protection window — i.e. literally rejecting could itself hang or run unbounded, which is the exact failure mode the watchdog exists to prevent. The externally observable contract the AC actually cares about — `CancellationError`/timeout thrown, return within the time limit — is met and tested (`cancellationCancelsPendingAsyncHostFunction`, `diagnosticCancellationForcesEarlyTermination`). Flagging this for whoever reviews: it is a considered, tested, safety-motivated narrowing, not an oversight, but it is a literal divergence from the AC's/plan's wording and a human may want to confirm that's acceptable.

    ### implement — changed
    - evidence: verified/completed pre-existing diff; updated task description checkboxes only (no source changes this pass) — `swift test --filter JSCInterpreter` 32/32 pass, full `swift test` 176/176 pass, `mcp__sah__review review working` 0 findings
    - next: ready for `/review`; human should confirm the cancellation-narrowing deviation noted above is acceptable
    task: ^yahbkg5
  timestamp: 2026-08-05T18:19:35.200990+00:00
position_column: doing
position_ordinal: '80'
title: '[MultiTool] JSCInterpreter promise pump with async host functions'
---
Repo: this repo. Basis: eventplan.md §"Async JavaScript". Independent of the Router tasks — pure interpreter work. (The Proxy trap for pending results is split into its own follow-up task.)

## What
Replace the v1 "all host functions are synchronous" premise in `Sources/FoundationModelsMultitool/Interpreter/` with a promise pump. The async-IIFE wrapper and settle guard already exist (JSCInterpreter.swift:419-423); what changes is that host calls become genuinely async.

- `Interpreter/Interpreter.swift`: add an async host function shape (e.g. `AsyncHostFunction` with `@Sendable ([InterpreterValue]) async throws -> InterpreterValue`) alongside the sync `HostFunction`. Per the plan's one-rule contract, sync stays for pure surface reads (`help`/`docs`) and void enqueuers (`notify`/`progress`); async is for everything that does Swift effects.
- `Interpreter/JSCInterpreter.swift`:
  - Install each async host function as a JS function that returns a Promise. The Swift body runs in a `Task`; on settle, hop back to the interpreter's serial queue (`DispatchQueue(label: "FoundationModelsMultitool.JSCInterpreter")` — the "JS thread"), resolve/reject the stored JS resolver, and let JSC drain the microtask queue. Interleaving happens only at `await` points; JS single-thread semantics hold.
  - Track every promise the bridge creates (registry keyed by promise id) for settle-before-return: the run yields no result until all created promises settle; a floating rejection becomes the run's error. This replaces the current `outcome.done == false` never-settled throw with a real bounded wait.
  - Keep the sandbox alive past `evaluateScript` until settlement (today `sandbox.tearDown()` runs in a `defer` — restructure so teardown happens after the pump drains or the watchdog fires).
  - Cancellation and watchdog timeout: reject all pending promises, drain the microtask queue, tear down within the existing `timeLimit` (reuse `WatchdogState`). A rejected promise is a JS exception at the `await` point with the same repairable message shape.
- A snippet's unawaited *returned* promise is handled at the boundary: `InterpreterResult`/outcome handling awaits a thenable final value so `return tools.x.y(...)` is correct.

## Acceptance Criteria
- [x] A snippet awaiting two async host functions via `Promise.all` runs them concurrently (verify with a fixture that records overlapping execution windows) — `promiseAllRunsAsyncHostFunctionsConcurrently`.
- [x] `tools.files.write(...); return "done"` style floating calls complete before the run returns; a floating rejection fails the run — `floatingAsyncCallSettlesBeforeReturn`, `floatingAsyncRejectionFailsRun`.
- [x] Cancellation mid-await rejects pending promises and returns within the time limit — `cancellationCancelsPendingAsyncHostFunction`. Implemented with a deliberate narrowing from the literal "reject each pending promise" wording: on a watchdog-forced termination (timeout or `isCancelled`), pending entries' backing `Task`s are cancelled and the promises are left permanently pending (never `resolve`/`reject`-settled) before immediate teardown, because settling a promise resumes JS execution (the microtask queue, any `.then`/`.catch`) outside the watchdog's own re-armed protection window — the same failure mode the watchdog exists to bound. See `PromiseRegistry.cancelAllPending` and `pumpUntilSettled` doc comments in `JSCInterpreter.swift`, and the task comment recording this decision.
- [x] Existing `JSCInterpreterTests` suite still green — 32/32 pass (`swift test --filter JSCInterpreter`).

## Tests
- [x] New cases in `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift`: async host function awaited top-level (`topLevelAwaitOfAsyncHostFunctionResult`); `Promise.all` fan-out concurrency (`promiseAllRunsAsyncHostFunctionsConcurrently`); settle-before-return value/rejection (`floatingAsyncCallSettlesBeforeReturn`, `unawaitedReturnedPromiseSettlesAtBoundary`, `floatingAsyncRejectionFailsRun`); cancellation-rejects-pending (`cancellationCancelsPendingAsyncHostFunction`, narrowed per the AC note above); sandbox teardown after settlement (`asyncHostFunctionDoesNotLeakTheSandbox`, `sandboxSurvivesMultipleSequentialAwaits`).
- [x] `swift test --filter JSCInterpreter` green (32/32); full `swift test` green (176/176, plus 6 gated-integration tests correctly skipped without `MULTITOOL_INTEGRATION`).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1