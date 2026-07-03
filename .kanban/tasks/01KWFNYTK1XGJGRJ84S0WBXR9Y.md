---
comments:
- actor: wballard
  id: 01kwksmvssp57mzxqym59wq1pp
  text: |-
    Fixed the 15hr hang in diagnosticCancellationForcesEarlyTermination.

    Root cause (confirmed with an isolated raw-JSC diagnostic, bypassing Sandbox/HostFunction machinery entirely): JSC's documented JSShouldTerminateCallback contract ("return false = grant one more window of the same duration") does NOT hold on this SDK (OS-27, Xcode 27, Swift 6.4). The callback fires exactly once; returning `false` with no further action leaves the script running unchecked forever — measured directly with a counting callback that logged 1 invocation at t=0.1s and then nothing for 8+ real seconds while evaluateScript never returned.

    Tested a second, distinct hypothesis: re-arming JSContextGroupSetExecutionTimeLimit synchronously, from within the callback itself (same thread), before returning `false`. This DOES work — 5 invocations at ~100ms spacing, clean termination at ~0.52s in the isolated repro. This is different from the prior agent's already-tested scenario (re-arming a long-committed window from another thread to force EARLY termination, which they correctly found doesn't work) — this is proactive self-renewal of a short window from the same thread, before the window naturally expires.

    Applied the fix to JSCInterpreter.swift: WatchdogState now stores the JSContextGroupRef and pollInterval, and shouldTerminate() calls a new private rearm() (re-issuing JSContextGroupSetExecutionTimeLimit with the same short window) before returning false. Corrected the file's doc comments to document the actual measured behavior (both experiments) with the same rigor as the existing M1 pin comment. Had to change WatchdogState's Sendable conformance to `@unchecked Sendable` since it now holds an OpaquePointer (JSContextGroupRef), which isn't Sendable — documented why that's safe (immutable pointer only used to call the thread-safe C API; the one mutable field is lock-protected).

    Verified: diagnosticCancellationForcesEarlyTermination and infiniteLoopTerminatedByWatchdog both pass, run 15x back-to-back with zero failures/flakiness/hangs (each run of the full JSCInterpreterTests suite completed in ~1.2s). No leftover swift-test/swiftpm-testing-helper processes after any run. swift build is clean.

    Isolated diagnostics kept at /private/tmp/claude-501/.../scratchpad/jscdiag.swift (reproduces the hang) and jscdiag2.swift (proves the fix) for reference — not part of the repo.

    Next: review and finish the rest of M10 scope (MultiToolConfiguration, logging, HardeningTests, README security model section) which was already partially started as uncommitted work.
  timestamp: 2026-07-03T10:51:00.281307+00:00
- actor: wballard
  id: 01kwktbgh3aa1sqbsja1gtj4t3
  text: |-
    M10 implementation complete and verified. Summary of remaining work after the watchdog fix (see prior comment):

    Two more bugs found and fixed while getting the already-started HardeningTests green:
    1. Sources/FoundationModelsMultitool/MultiTool.swift `makePreamble`: `var tools = {};` -> `globalThis.tools = {};`. The whole preamble+snippet runs inside one wrapping IIFE (JSCInterpreter.evaluate's `wrapped` string), so `var tools` was only a function-local binding, never a true `globalThis` property — this broke the two HardeningTests that enumerate `Object.getOwnPropertyNames(globalThis)` to check the sandbox's exact reachable surface against README.md.
    2. Tests/FoundationModelsMultitoolTests/HardeningTests.swift `rawJSContextGlobals()`: now explicitly subtracts `"console"` from the raw-JSContext baseline, since a bare `JSContext()` already ships a default `console` on this SDK (measured directly) that `JSCInterpreter.installConsole` unconditionally replaces — so it's rightly counted as part of what this package controls, not the untouched baseline.

    Final state, all verified fresh in this session with hard timeouts throughout, no hung processes at any point:
    - `swift build`: clean, exit 0.
    - `swift test` (full suite): 164/164 tests pass in ~1.0s, across 14 suites.
    - `swift test --filter HardeningTests`: 17/17 pass (MultiToolConfiguration defaults/clamping, cancellation x3 including a 40-iteration concurrent stress test, all 5 limit boundaries, sandbox-surface enumeration, README<->code set-equality).
    - `swift test --filter JSCInterpreterTests`: 14/14 pass, including the fixed diagnostic and the original M1 watchdog-timeout test.
    - Full suite re-run 3x back to back with zero flakiness.

    M10 scope review: MultiToolConfiguration.swift (execution time limit, return/console caps, max agent turns, max repair turns, all clamped, all defaults matching pre-M10 behavior) is threaded through MultiTool.init and MultiToolAgent.init. os.Logger present at every seam plan.md calls for: JSCInterpreter (snippet start/end+duration), MultiTool (tools.* invocation start/end/failure, split validation-failure vs. tool-failure severity), MultiToolAgent (repair turns), Librarian (pre-filter cuts, pre-existing M6 code, confirmed still present). README.md's "## Security model" section (Injected globals, watchdog/caps bound, what's NOT guaranteed + escape hatches) is machine-checked against the runtime-enumerated sandbox globals by HardeningTests.

    Adversarial double-check (via really-done's gate) returned PASS, independently re-running the test suite and specifically scrutinizing the watchdog re-arm for reentrancy/leak/teardown-ordering bugs, the `@unchecked Sendable` justification, the `globalThis.tools` change's interaction with the grouped-tools preamble lines, and the console-subtraction fix — no issues found.

    Leaving the task in `doing` per the implement process, ready for /review.
  timestamp: 2026-07-03T11:03:22.403906+00:00
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
- 01KWFNWYGEJHW6X7VV7T92T9K1
- 01KWFNWJECBNSZCANVMNTR3Z8J
position_column: doing
position_ordinal: '80'
title: 'M10: Hardening — cancellation, limits, logging, security model'
---
## What
Per plan.md M10:
- **Cancellation:** cancelling the task running `MultiToolAgent.respond(to:)` or `MultiTool` execution terminates the in-flight snippet (watchdog force-terminate) and propagates `CancellationError`; no leaked JS thread or semaphore deadlock.
- **Limits tuned + configurable:** a `MultiToolConfiguration` (execution time limit, return-size cap, console cap, max agent turns, max repair attempts — the knob M4b defaults to 1) with documented defaults, threaded through `MultiTool`/`MultiToolAgent`.
- **Logging:** `os.Logger` (subsystem = module) at the seams — snippet start/end + duration, each tools.* invocation, validation failures, librarian pre-filter cuts (M6 code), repair turns.
- **Security model written down:** a `## Security model` section in `README.md` — a snippet reaches ONLY the wrapped tools (deny-by-default JSContext, injected globals enumerated), what the watchdog/caps bound, what is NOT guaranteed (in-snippet args are not token-constrained; the escape hatches — direct guided calls on a Router model, Apple's token-level loop only in a built-in session).

## Acceptance Criteria
- [x] Cancellation mid-snippet (long-running JS) returns `CancellationError` within the time limit and leaves no live interpreter thread
- [x] Each configuration limit is enforced and covered by a test at its boundary
- [x] Sandbox-surface test: the set of reachable globals in a fresh run context is exactly the documented list
- [x] README↔code sync is machine-checked: `HardeningTests` parses the README's enumerated global list and asserts set-equality with the runtime-enumerated sandbox globals — drift fails CI

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/HardeningTests.swift` — cancellation, each limit boundary, sandbox global-surface enumeration, README global-list set-equality parse
- [x] `swift test --filter HardeningTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.