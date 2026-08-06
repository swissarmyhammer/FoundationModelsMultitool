---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kzbgvsp3dhkjgs5f67e5qpvp
  text: |-
    Research + design notes for the next agent.

    **Dependency resolution.** `swift package update FoundationModelsRouter` (targeted, not a bare update) moved Router from af9112fc to `main` @ b5bf2ba, which carries `Hosting/{ElevatingTool,ToolContext,SessionMailbox,OperationEvent,OperationEventSink,OperationOutcome,Elicitation,ForkableTool}.swift`. `Package.resolved` is **gitignored in this repo** (`.gitignore:17`), so the pin move is NOT part of the change set — the manifest tracks the `main` branch and each machine resolves for itself. `swift build` stayed green through the bump; no unrelated Router-side fallout.

    **The engine entry point.** `ToolElevation.wrapping(_:sessionID:mailbox:sink:configuration:)` is the right seam, not `ElevatingTool.init` directly: `ElevatingTool` requires `Output == String`, and `ToolElevation.wrapping` falls back to `ContextBindingTool` for any other `Output`. Both decorators mint their own `completionToken` and bind `ToolContext.$current` explicitly inside their own `Task`, and both preserve the wrapped tool's `Arguments`/`Output`, so `RunBinding.invoke` can cast the result back to `any Tool<T.Arguments, T.Output>` and call through. That is what satisfies the card's central constraint for free — nothing on this route reads an inherited task local.

    **Discovery / constraint worth recording: `ToolContext` does not expose its `sink`.** `ToolContext.sink` is `private` on Router `main`, and Router publishes no accessor or "derive a child context" API. So a nested host (MultiTool) cannot hand the engine the session's *real* upstream sink; the only egress a captured context publishes is `ToolContext.post(_:)`, which **re-stamps** what it forwards with its own `tool`/`op`/`correlationID`.

    Consequence, implemented and documented in `AmbientUpstreamSink`: an inner `tools.*` run's events reach the session's outbox on the **outer `runCode` run's** correlation — the operation the session actually issued — while the inner run's own `completionToken` stays on the run plane (the engine's `RunEventFunnel` addresses the mailbox by it, and the inner tool reads it from its own `ToolContext.current`). Every acceptance criterion still holds, and this matches eventplan.md §"MultiTool is a host and an emitter" ("MultiTool's sink updates the mailbox first and then sends the event upstream"). If a later phase needs the inner correlation preserved upstream, that needs a Router-side change (a public `sink` accessor or a re-stamping derivation initializer on `ToolContext`) — it cannot be done from this repo.

    **Executor.** The card asks the binding to hold "the interpreter's serial executor". It does not store one, deliberately: `JSCInterpreter`'s `PromiseRegistry` already keys every bridge-created promise by id and settles it from the interpreter's own dedicated worker queue in `pumpUntilSettled`, so the interpreter that created a promise is always the one that settles it. Storing a second handle would be a redundant copy of an invariant the interpreter already owns; the reasoning is written into `RunBinding`'s type doc.

    **No-session degradation is preserved on purpose.** `RunBinding.ambient` is `nil` when no session bound a context (every existing unit suite), and `ToolInvoker` then calls the tool natively, exactly as before. That keeps the *absence* of a run plane observable for the follow-up sandbox-globals card (^e76zk99), which needs to reject `status`/`wait`/`cancel`/`elicit` with "no session context".

    **Why `asyncHostFunctions` stopped being precomputed.** Each `AsyncHostFunction` now closes over the invocation's `RunBinding`, so it cannot be built at `init` time. `MultiTool` precomputes the stable half instead (`liveTools`: host-function name ↔ live tool) and rebuilds the closures per call via `makeAsyncHostFunctions(binding:)`.
  timestamp: 2026-08-06T12:30:40.323629+00:00
- actor: claude-code
  id: 01kzbgw0wx5mgwzxd2df2epe2r
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Invocation/RunBinding.swift (new), Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift, Sources/FoundationModelsMultitool/MultiTool.swift, Tests/FoundationModelsMultitoolTests/RunBindingTests.swift (new), Tests/FoundationModelsMultitoolTests/Fixtures/RunBindingFixtures.swift (new)
    - TDD: the four new tests were written first and failed to compile on `cannot find 'RunBinding' in scope`, then went green against the implementation.
    - tests: `swift test` → 199 tests in 19 suites passed (was 195; +4 new), 0 failures; gated integration suites skipped as expected. `swift build --build-tests` → zero warnings except the known pre-existing mlx-swift "missing creator for mutated node". LSP `check working` → 0 errors, 0 warnings.
    - next: /review
  timestamp: 2026-08-06T12:30:47.709529+00:00
- actor: claude-code
  id: 01kzbh4f5gsawm3jc2ye318d4e
  text: |-
    ### test — green
    - evidence: `swift build` — clean (only pre-existing mlx-swift build-manifest warning "missing creator for mutated node", unrelated to this change); `swift test` — 199 tests in 19 suites passed, 0 failed, 0 warnings (baseline 195, +4 new). 6 tests in 3 suites skipped, all under the `MULTITOOL_INTEGRATION` gate (IntegrationGate.swift), correctly left skipped per instruction.
    - flakiness check: full `swift test` run 10 times consecutively — 199/199 passed every time, no variance in timing/ordering. `swift test --filter RunBindingTests` run in isolation 5 times — 4/4 passed every time (parallel Promise.all correlation, cross-instance isolation, detached-Task re-read-is-nil, slow-inner-call-no-elevation).
    - no source files were modified during this test pass; git working tree unchanged by testing.
    - next: ready for review.

    step: test
    outcome: green
    evidence: swift test — 199 passed, 0 failed, 0 skipped-outside-gate (6 skipped under MULTITOOL_INTEGRATION gate as instructed), 0 warnings (excluding known pre-existing mlx-swift manifest warning); repeated 10x full runs + 5x isolated RunBindingTests runs, all green
    task: 01KZ6N3KMERCMS4DCMEFHR27KF
  timestamp: 2026-08-06T12:35:24.464899+00:00
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: doing
position_ordinal: '80'
title: '[MultiTool] Route tools.* through ElevatingTool with RunBinding'
---
CROSS-BOARD PREREQUISITE: the Router-side foundation (vocabulary move → SessionMailbox → ToolContext → ElevatingTool engine, tasks tagged `router-first` on ../FoundationModelsRouter's own kanban board) must be done and pushed to Router `main` before this task can build. Verify `ElevatingTool` and `ToolContext` exist on Router `main` (`swift package update` here resolves them) before starting.

Repo: this repo. Basis: eventplan.md §"Async JavaScript" (session affinity across the seam), §"Elevation" (the code-mode mount: elevation off), §"The constraint boundary" (inner calls never elevate).

## What
- `Invocation/ToolInvoker.swift` + the tools.* host-function glue in `MultiTool.swift`: send each inner `tools.*` call through the shared `ElevatingTool` engine with elevation off. Inner calls run until they complete, bounded by `timeout`; only the outer `runCode` elevates. The engine still owns correlation, events, and outcomes for inner calls.
- New `RunBinding` (one per `runCode` invocation), captured when the ambient context is bound: holds the `ToolContext` (session identity, mailbox reference, sink), the outer `completionToken`, and the interpreter's serial executor. Each promise carries the binding.
- The JS thread is not a Swift task — a JSC callback lands outside every task tree, so nothing may rely on task-local inheritance across the seam. Each inner call's `Task` closure re-binds `ToolContext.$current` explicitly from the binding and mints its own per-call `completionToken` from the captured context. Parallel `Promise.all` calls therefore correlate independently and post to the same session's mailbox.
- Settlement resolves the promise on the binding's executor, keyed by promise id. Two sessions sharing one registry can never cross-route because each invocation captured its own binding.
- Validation layering unchanged: `ToolInvoker`'s two layers still run, and their repairable errors reject the promise with identical message text.

## Acceptance Criteria
- [x] An inner call slower than the configured `waitSeconds` still returns its real value to the snippet (never a pending envelope) — elevation is off on this path
- [x] Two parallel inner calls under `Promise.all` carry distinct `completionToken`s and both post to the same session's mailbox/sink
- [x] With two MultiTool instances over one registry, events from a run on instance A never reach instance B's sink (binding capture, not inheritance)
- [x] A detached `Task` inside a tool that re-reads `ToolContext.current` gets `nil` (capture-at-start enforced)
- [x] Full `swift test` green in this repo

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/RunBindingTests.swift`: slow-inner-call-no-elevation; parallel distinct correlation; cross-instance isolation; explicit re-bind (fixture tool records `ToolContext.current?.completionToken`)
- [x] `swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1