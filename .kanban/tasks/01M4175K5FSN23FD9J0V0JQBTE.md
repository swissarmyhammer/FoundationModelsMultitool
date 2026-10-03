---
assignees:
- claude-code
depends_on:
- 01M413YDNNJSNTFCJEY71CBG70
position_column: todo
position_ordinal: 8a80
title: Remove the dead InterpreterError.Kind.timeout and its readers
---
## What
After `^8v2fv2z`, no code makes an `InterpreterError` of kind `.timeout`: `JSCInterpreter` has no clock, and `Interpreter` has no clock requirement after `^71cbg70`. The case and its readers are dead code, and their docs state a watchdog timeout that does not occur.

- [ ] `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift`: remove `InterpreterError.Kind.timeout`, and update the docs of `Kind` and `InterpreterError.init` ("or a watchdog timeout", "as with a `.timeout`").
- [ ] `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift`: remove the `.timeout` arm ("The snippet timed out").
- [ ] `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry+Metrics.swift`: remove the `.timeout` branch of the outcome. Keep `MultitoolTelemetry.ErrorKindValue.timeout` if MCP calls still use it (`MCPServer+CallSpan.swift`).
- [ ] `Sources/FoundationModelsMultitool/MultiTool.swift`: update the `call` doc ("or a watchdog timeout").
- [ ] Remove or change the tests that make `InterpreterError(kind: .timeout, ...)` only to test a dead path (for example `ResultRendererTests`).

## Acceptance Criteria
- [ ] `rg -n "kind: \.timeout|case \.timeout|watchdog timeout" Sources Tests` finds no `InterpreterError` use.
- [ ] The build has no new warnings.

## Tests
- [ ] `swift build` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #tech-debt