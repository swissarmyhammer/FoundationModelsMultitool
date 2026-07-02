---
comments:
- actor: wballard
  id: 01kwhnw1reztxff6nry4chm5x5
  text: |-
    Implementation complete via TDD.

    Created:
    - Sources/FoundationModelsMultitool/MultiTool.swift (new) — `MultiTool: Tool` struct (moved base type declaration here from MultiToolBuilder.swift, which previously held it as a bare `enum MultiTool {}` namespace placeholder), `MultiTool.Registry` (pairs the rendered `APISurface` with a `[String: any Tool]` map keyed by fully-qualified path, plus `isDirectMode`/`directMode()`/`affordances`/`supportsFindAPIs`), `RunCodeArguments`.
    - Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift + Fixtures/MultiToolExecutionFixtures.swift (new) — 5 tests covering all acceptance criteria.

    Modified:
    - Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift — removed the base `enum MultiTool {}` declaration (moved to MultiTool.swift); added `Builder.buildRegistry() throws -> MultiTool.Registry` as the primary build path (renders + validates, same loop as before, now also collecting a `path -> any Tool` map); `build() throws -> APISurface` is now a one-line delegate (`try buildRegistry().surface`) — fully behavior-preserving, existing BuilderSurfaceTests pass unmodified.

    Design decisions:
    - `tools.*` installation: `HostFunction` (M1) only supports flat global callables (no nested-object install path — `InterpreterValue` has no function case). So `MultiTool` installs each wrapped tool as a positionally-named flat global (`__tool0`, `__tool1`, ...) and prepends a small JS glue preamble that assigns each into its real `tools.<name>` / `tools.<group>.<name>` position, ahead of the user's snippet in the same `code` string handed to `interpreter.run`.
    - v1 async bridge (plan Resolved #1): `invokeBlocking` (HostFunction body, runs on JSCInterpreter's own dedicated worker thread, never main) spawns an unstructured `Task` to run the wrapped tool's real async `call(arguments:)` on Swift's cooperative pool, then blocks that dedicated worker thread on a `DispatchSemaphore` until the Task signals via a lock-protected `Result` box. Documented tradeoff in the code: this is safe because the dedicated JSC thread is never one of the cooperative pool's threads, but the spawned Task still needs a free cooperative thread — under full pool saturation this is a real starvation/deadlock risk, not just reduced throughput. Noted the JSC microtask/promise-pump upgrade as the eventual fix.
    - `MultiTool.call(arguments:)` additionally wraps the synchronous `interpreter.run(...)` in `withCheckedThrowingContinuation` + `DispatchQueue.global().async` so the *outer* async call doesn't tie up its own cooperative-pool thread for the run's duration either — an extra safety margin beyond what the task strictly asked for, justified by JSCInterpreter's own doc comment anticipating this ("blocking must not happen on the caller's thread").

    Review round 1 (mcp__sah__review) caught a real bug: `makePreamble` unconditionally emitted `tools.<path> = __toolN;` for every surface entry, but `makeHostFunctions` skips installing a host function when `registry.tools[path]` is missing — so an unmatched entry would reference an undeclared JS global (ReferenceError) instead of degrading to `undefined` as documented. Fixed by making `makePreamble` take the full `Registry` and skip entries the same way `makeHostFunctions` does. Review round 2: 0 findings.

    Verification: `swift build` clean (no new warnings). `swift test` — 104/104 passing (up from 99 pre-task), including the async-bridge test which asserts `Thread.isMainThread == false` inside the wrapped tool's `call`.

    Adversarial double-check agent dispatched to verify before handoff.
  timestamp: 2026-07-02T15:06:32.590304+00:00
- actor: wballard
  id: 01kwhp2cwaw0t8c04kxb6azwvp
  text: |-
    Adversarial double-check agent verdict: PASS. It independently re-ran `swift build` and `swift test` (104/104 green, including BuilderSurfaceTests 9/9 and MultiToolExecution 5/5 individually confirmed), traced the invokeBlocking semaphore/lock pairing for missed/double-signal races (none found), confirmed the continuation in MultiTool.run resumes exactly once on every path, verified all 5 acceptance-criteria tests are non-vacuous (each assertion actually exercises the claimed behavior, not just a happy-path pass), and checked doc-comment completeness/no force-unwraps/no duplicated logic. Only note: the task's own checkbox markdown was still unchecked at review time — fixed now via update task (all boxes checked, progress 1.0).

    Task is green and ready for /review. Leaving in `doing` per the implement skill's process (review owns the doing -> review transition).
  timestamp: 2026-07-02T15:10:00.586775+00:00
depends_on:
- 01KWFNS1CDSSQ3NJXAPV1PX1XJ
- 01KWFNT7BY92073MGCF6GRQ8NH
- 01KWFNTK6Y5PAQBFECXDHPST6P
- 01KWFNTYPAEZ6Y2VPH7G0369BW
position_column: doing
position_ordinal: '80'
title: 'M4a: MultiTool runCode execution — tools.* installed in the sandbox'
---
## What
Per plan.md M4 (execution half — no model needed):
- `Sources/FoundationModelsMultitool/MultiTool.swift` — the `runCode` core, conforming to `FoundationModels.Tool` (so it can also drop into an Apple built-in session): holds the built catalog + wrapped `[any Tool]`; per call builds a fresh interpreter, installs each tool as `tools.<name>` / `tools.<group>.<name>` closures that bridge into `ToolInvoker`, runs the snippet, renders via `ResultRenderer`.
- The v1 async bridge (plan Resolved #1): interpreter runs off the main thread; each `tools.X()` blocks the JS thread on a semaphore while the async `tool.call` runs on the cooperative pool.
- `registry.directMode()` flag on the built artifact (runCode-only surface; discovery skipped).

## Acceptance Criteria
- [x] A snippet composing two mock tools (`map` over one's array output, calling the other per element) returns only the final value — intermediates absent from the rendered output
- [x] `tools.github.<name>` grouped calls dispatch to the right tool
- [x] An async (delayed) mock tool's result arrives correctly through the blocking bridge, off the main thread
- [x] A mis-called tool surfaces ResultRenderer's repairable error text as the runCode result (not a crash)
- [x] `registry.directMode()` produces a runCode-only surface: it reports no findAPIs affordance and its rendered surface metadata says so — asserted in MultiToolExecutionTests

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift` — two-mock-tool composition, grouping dispatch, async bridge (tool that `Task.sleep`s), error path, directMode surface assertion
- [x] `swift test --filter MultiToolExecutionTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.