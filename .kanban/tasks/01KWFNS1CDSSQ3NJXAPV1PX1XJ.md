---
depends_on:
- 01KWFNRM5VSWGD37H2YJ7CMBN2
position_column: todo
position_ordinal: '8180'
title: 'M1: Interpreter protocol + JSCInterpreter with timeout watchdog'
---
## What
Per plan.md M1 (no model needed):
- `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift` — protocol: `run(code: String, installing: [HostFunction]) throws -> InterpreterResult` (returnValue as JSON-encodable, console lines, thrown → typed `InterpreterError`). Design the seam so JSC is swappable.
- `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift` — fresh `JSContext` per run (deny-by-default: only injected `console`, `JSON`, host functions reachable); capture `return` value + `console.log`; map JS exceptions (message, line) to `InterpreterError`.
- Time-limit watchdog: extern-declare `JSContextGroupSetExecutionTimeLimit` + `JSShouldTerminateCallback` (symbol lives in `JSContextRefPrivate.h`, not the public header set — declare it ourselves). **Pin: confirm the extern-declare compiles/links under the OS-27 SDK**; if not, implement the documented fallback (dedicated thread, abandon context on timeout) and record which path was taken in code docs.
- Run interpreter off the main thread (groundwork for the M4 blocking async bridge).

## Acceptance Criteria
- [ ] A snippet's `return` value round-trips out as JSON
- [ ] `console.log` lines are captured in order
- [ ] A JS throw surfaces as `InterpreterError` with message + location
- [ ] An infinite loop (`while(true){}`) is terminated by the watchdog within the configured limit
- [ ] A fresh context per run: globals set in run N are absent in run N+1

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift` — return capture, console capture, exception mapping, statelessness across runs, watchdog timeout (with a generous CI-safe limit)
- [ ] `swift test --filter JSCInterpreterTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.