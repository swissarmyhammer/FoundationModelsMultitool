---
comments:
- actor: wballard
  id: 01kwg06zhphe48x2a8vywe8mqz
  text: |-
    Implemented via TDD. Wrote Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift first (7 tests covering all acceptance criteria), confirmed RED via `swift build --build-tests` failing with "cannot find 'JSCInterpreter' in scope" (feature genuinely missing, not a typo), then implemented:

    - Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift — `Interpreter` protocol, `InterpreterValue` (JSON-shaped Codable enum used for both return values and HostFunction args/results, keeping the protocol engine-agnostic), `HostFunction`, `InterpreterResult`, `InterpreterError` (with `.exception`/`.timeout` kinds).
    - Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift — JavaScriptCore-backed conformer.

    Watchdog pin resolved: the primary extern-declare approach (`@_silgen_name` binding directly to `JSContextGroupSetExecutionTimeLimit`/`JSContextGroupClearExecutionTimeLimit`, mirroring WebKit's `JSContextRefPrivate.h`) compiles and links cleanly under the OS-27 SDK (Xcode 27, Swift 6.4). Verified two ways before writing code: (1) confirmed `JSContextRefPrivate.h` is genuinely absent from the public header set (`JavaScriptCore.framework/Headers` only ships `JSContextRef.h`); (2) confirmed both symbols are still listed in `JavaScriptCore.framework/JavaScriptCore.tbd` (`_JSContextGroupSetExecutionTimeLimit`, `_JSContextGroupClearExecutionTimeLimit}`) — the linkable stub the linker resolves against. No fallback (dedicated thread + abandon context) was needed; this is documented in code comments at the top of JSCInterpreter.swift.

    Other implementation notes:
    - Interpreter runs on a dedicated `DispatchQueue` (never the caller's thread), per the "groundwork for M4" requirement — `run()` does `queue.sync { ... }`.
    - Snippet is wrapped as `"(function(){\(code)\n})()"` (opening brace prepended to the snippet's own first line, not on its own line) so a bare top-level `return` works AND reported exception line numbers match the caller's original source 1:1 — verified by a test asserting the exact line of a nested `throw`.
    - Return value and HostFunction args/results round-trip through the sandboxed context's own `JSON.stringify`/`JSON.parse` (not Foundation bridging), so conversion never reaches outside the standard injected surface.
    - Watchdog termination is detected via a `WatchdogState` flag (set from the C callback via `Unmanaged.passUnretained`), checked *before* the captured-exception path, since JSC's watchdog-forced termination isn't guaranteed to also populate a normal catchable JS exception.

    Verification: `swift build` and `swift test` both green — 8/8 tests (7 new JSCInterpreterTests + the existing Scaffold test), zero failures, zero warnings beyond a pre-existing unrelated mlx-swift build-system warning present since M0. Watchdog test terminates `while(true){}` in ~1.06s against a configured 1.0s limit, bounded by an outer 10s assertion so a broken watchdog can't hang CI.

    Refactored `JSCInterpreter.evaluate` to extract sandbox setup/teardown into a private `Sandbox` struct + `makeSandbox` helper, keeping functions under ~50 lines per the coding standard.

    Sent to adversarial double-check (via really-done) before leaving in doing for review.
  timestamp: 2026-07-01T23:28:47.670267+00:00
- actor: wballard
  id: 01kwg0qz5sst372x2c074z2qcy
  text: |-
    Adversarial double-check (via really-done) round 1 returned REVISE with 6 concrete findings — all fixed, not just logged:

    1. `WatchdogState.timedOut` was a plain unsynchronized `Bool` mutated from the `@convention(c)` watchdog callback, relying on an unstated thread-affinity assumption. Fixed: `WatchdogState` is now `final class WatchdogState: Sendable` backed by `OSAllocatedUnfairLock<Bool>` (`import os`), with `timedOut` as a lock-guarded computed property and a new `markTimedOut()` lock-guarded mutator.
    2. No test covered a `HostFunction` that throws. Added `hostFunctionThrowSurfacesAsInterpreterError`.
    3. `InterpreterValue`/JSON round-trip was asymmetric on non-finite numbers: JS→Swift silently degraded NaN/Infinity to `null` (via JS's own `JSON.stringify`), but Swift→JS let `JSONEncoder` throw a raw `EncodingError` that got stringified into an ugly JS exception message. Fixed in `InterpreterValue.encode(to:)`: the `.number` case now checks `value.isFinite` and encodes `nil` instead, matching the JS-side behavior exactly — both directions now agree, and `JSONEncoder` never throws for this case. Added `hostFunctionNonFiniteReturnValueRoundTripsAsNull` (this one was genuine RED before the fix — caught `EncodingError.invalidValue` bubbling up) and `hostFunctionNonFiniteArgumentRoundTripsAsNull` (was already correct, now pinned).
    4. No test distinguished a JS syntax error from a runtime throw, despite `InterpreterError.Kind.exception`'s doc claiming to cover both. Added `syntaxErrorSurfacesAsInterpreterError`.
    5. No test covered concurrent `run()` calls from multiple threads on one `JSCInterpreter`, despite the type's thread-safety doc claims. Added `concurrentRunsStayIsolated` (async test, 20 concurrent `run()` calls via `withThrowingTaskGroup`, asserts per-call isolation).
    6. No test covered the trailing-`//`-comment-before-the-injected-wrapper case the code comments explicitly reason about. Added `trailingLineCommentBeforeWrapperIsHandled`.

    Round 2 double-check re-verified all six fixes independently (including tracing the pre-fix NaN failure mode and confirming the `OSAllocatedUnfairLock` usage has no deadlock risk) and returned **PASS**.

    Final verification (this session, fresh): `swift build` clean, `swift test` → 14/14 pass (13 JSCInterpreterTests + 1 Scaffold), zero failures, zero warnings beyond the pre-existing unrelated mlx-swift build-system warning. Re-ran the interpreter suite 3x consecutively to rule out flakiness in the new concurrency/timing-sensitive tests — stable every time.

    All acceptance criteria and required tests are checked off. Task is green and left in `doing` for `/review` per the implement skill's contract.
  timestamp: 2026-07-01T23:38:04.345817+00:00
depends_on:
- 01KWFNRM5VSWGD37H2YJ7CMBN2
position_column: doing
position_ordinal: '80'
title: 'M1: Interpreter protocol + JSCInterpreter with timeout watchdog'
---
## What\nPer plan.md M1 (no model needed):\n- `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift` — protocol: `run(code: String, installing: [HostFunction]) throws -> InterpreterResult` (returnValue as JSON-encodable, console lines, thrown → typed `InterpreterError`). Design the seam so JSC is swappable.\n- `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift` — fresh `JSContext` per run (deny-by-default: only injected `console`, `JSON`, host functions reachable); capture `return` value + `console.log`; map JS exceptions (message, line) to `InterpreterError`.\n- Time-limit watchdog: extern-declare `JSContextGroupSetExecutionTimeLimit` + `JSShouldTerminateCallback` (symbol lives in `JSContextRefPrivate.h`, not the public header set — declare it ourselves). **Pin: confirm the extern-declare compiles/links under the OS-27 SDK**; if not, implement the documented fallback (dedicated thread, abandon context on timeout) and record which path was taken in code docs.\n- Run interpreter off the main thread (groundwork for the M4 blocking async bridge).\n\n## Acceptance Criteria\n- [x] A snippet's `return` value round-trips out as JSON\n- [x] `console.log` lines are captured in order\n- [x] A JS throw surfaces as `InterpreterError` with message + location\n- [x] An infinite loop (`while(true){}`) is terminated by the watchdog within the configured limit\n- [x] A fresh context per run: globals set in run N are absent in run N+1\n\n## Tests\n- [x] `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift` — return capture, console capture, exception mapping, statelessness across runs, watchdog timeout (with a generous CI-safe limit)\n- [x] `swift test --filter JSCInterpreterTests` → passes\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.