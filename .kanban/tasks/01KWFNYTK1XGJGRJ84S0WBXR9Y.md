---
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
- 01KWFNWYGEJHW6X7VV7T92T9K1
- 01KWFNWJECBNSZCANVMNTR3Z8J
position_column: todo
position_ordinal: '8e80'
title: 'M10: Hardening — cancellation, limits, logging, security model'
---
## What
Per plan.md M10:
- **Cancellation:** cancelling the task running `MultiToolAgent.respond(to:)` or `MultiTool` execution terminates the in-flight snippet (watchdog force-terminate) and propagates `CancellationError`; no leaked JS thread or semaphore deadlock.
- **Limits tuned + configurable:** a `MultiToolConfiguration` (execution time limit, return-size cap, console cap, max agent turns, max repair attempts — the knob M4b defaults to 1) with documented defaults, threaded through `MultiTool`/`MultiToolAgent`.
- **Logging:** `os.Logger` (subsystem = module) at the seams — snippet start/end + duration, each tools.* invocation, validation failures, librarian pre-filter cuts (M6 code), repair turns.
- **Security model written down:** a `## Security model` section in `README.md` — a snippet reaches ONLY the wrapped tools (deny-by-default JSContext, injected globals enumerated), what the watchdog/caps bound, what is NOT guaranteed (in-snippet args are not token-constrained; the escape hatches — direct guided calls on a Router model, Apple's token-level loop only in a built-in session).

## Acceptance Criteria
- [ ] Cancellation mid-snippet (long-running JS) returns `CancellationError` within the time limit and leaves no live interpreter thread
- [ ] Each configuration limit is enforced and covered by a test at its boundary
- [ ] Sandbox-surface test: the set of reachable globals in a fresh run context is exactly the documented list
- [ ] README↔code sync is machine-checked: `HardeningTests` parses the README's enumerated global list and asserts set-equality with the runtime-enumerated sandbox globals — drift fails CI

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/HardeningTests.swift` — cancellation, each limit boundary, sandbox global-surface enumeration, README global-list set-equality parse
- [ ] `swift test --filter HardeningTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.