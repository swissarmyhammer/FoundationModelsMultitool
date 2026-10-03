---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41jf4ckhp1vjtk0j210wham
  text: |-
    Research done.
    - Readers of `InterpreterError.Kind.timeout`: `InterpreterError.Kind.repairableErrorSummary` (ResultRenderer.swift) and `MultitoolTelemetry.interpreterOutcome(of:)` (MultitoolTelemetry+Metrics.swift). `interpreterOutcome(of:)` has one caller, `JSCInterpreter` `recordEnd(of:since:)`. Without the `.timeout` branch it is the same as `MultitoolTelemetry.outcome(of:)` (MultitoolTelemetry+Tracing.swift), thus I remove it and the caller uses `outcome(of:)`.
    - `OutcomeValue.timedOut` and `ErrorKindValue.timeout` stay: `MCPServer+CallSpan.swift` still uses them.
    - One more stale doc that the card does not list: `TypedMockDryRun.apiUsageFailure` says "A watchdog timeout counts as a failure" and "Its own time limit bounds the run". The acceptance `rg` matches "watchdog timeout" there, thus I change it. ^8v2fv2z records the user decision that searchTools has no timeout.
    - Only one test makes `kind: .timeout`: `ResultRendererTests.timeoutErrorIsDistinguishableFromException`. It tests only the dead path, thus I delete it.
    - `Kind` keeps one case, `.exception`. 31 call sites (17 in JSCInterpreter.swift, 14 in tests) and external `Interpreter` conformers construct `InterpreterError(kind: .exception, ...)`. To remove the enum would break each of them. Removing only the `.timeout` case is the smallest public API change.
  timestamp: 2026-10-03T19:04:47.251062+00:00
- actor: claude-code
  id: 01m41jpq29da5nw2r18pcj56m6
  text: |-
    ### implement — changed
    - evidence: 7 code files. `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift` (remove `Kind.timeout`; docs of `Kind` and `InterpreterError.init`), `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift` (remove the `.timeout` arm), `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry+Metrics.swift` (remove `interpreterOutcome(of:)`), `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift` (`recordEnd` calls `MultitoolTelemetry.outcome(of:)`), `Sources/FoundationModelsMultitool/MultiTool.swift` (`call` doc), `Sources/FoundationModelsMultitool/Discovery/TypedMockDryRun.swift` (`apiUsageFailure` doc: no watchdog timeout, no clock), `Tests/FoundationModelsMultitoolTests/ResultRendererTests.swift` (delete `timeoutErrorIsDistinguishableFromException`, the one test of the dead path). RED: `swift build --build-tests` after the case removal, 1 error: "type 'InterpreterError.Kind' has no member 'timeout'" in MultitoolTelemetry+Metrics.swift. GREEN: `swift test --filter 'ResultRendererTests|MetricsTests|TypedMockDryRunTests|JSCInterpreterTests|SampleSnippetTests'` 5 suites passed; `swift test` 1809 tests in 151 suites passed, 0 failures. The only build warning is the SwiftPM "missing creator for mutated node" on the mlx-swift bundle; earlier cards record it, thus it is not new. Acceptance `rg -n "kind: \.timeout|case \.timeout|watchdog timeout" Sources Tests` gives 0 lines.
    - public API decision: `InterpreterError.Kind` stays, with the one case `.exception`. The public change is only the removal of the `.timeout` case. To remove the enum would also remove `InterpreterError.kind` and the `kind:` parameter of the public `init`, and break 31 call sites in this repo and each external `Interpreter` conformer. The `Kind` doc now says why the enum stays. A host that switched on `.timeout` gets a compile error; that path never ran after ^8v2fv2z.
    - `OutcomeValue.timedOut` and `ErrorKindValue.timeout` stay: `MCPServer+CallSpan.swift` uses them.
    - next: run `/review` on this task.
  timestamp: 2026-10-03T19:08:55.753986+00:00
depends_on:
- 01M413YDNNJSNTFCJEY71CBG70
position_column: doing
position_ordinal: '8180'
title: Remove the dead InterpreterError.Kind.timeout and its readers
---
## What
After `^8v2fv2z`, no code makes an `InterpreterError` of kind `.timeout`: `JSCInterpreter` has no clock, and `Interpreter` has no clock requirement after `^71cbg70`. The case and its readers are dead code, and their docs state a watchdog timeout that does not occur.

- [x] `Sources/FoundationModelsMultitool/Interpreter/Interpreter.swift`: remove `InterpreterError.Kind.timeout`, and update the docs of `Kind` and `InterpreterError.init` ("or a watchdog timeout", "as with a `.timeout`").
- [x] `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift`: remove the `.timeout` arm ("The snippet timed out").
- [x] `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry+Metrics.swift`: remove the `.timeout` branch of the outcome. Keep `MultitoolTelemetry.ErrorKindValue.timeout` if MCP calls still use it (`MCPServer+CallSpan.swift`).
- [x] `Sources/FoundationModelsMultitool/MultiTool.swift`: update the `call` doc ("or a watchdog timeout").
- [x] Remove or change the tests that make `InterpreterError(kind: .timeout, ...)` only to test a dead path (for example `ResultRendererTests`).

## Acceptance Criteria
- [x] `rg -n "kind: \.timeout|case \.timeout|watchdog timeout" Sources Tests` finds no `InterpreterError` use.
- [x] The build has no new warnings.

## Tests
- [x] `swift build` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #tech-debt #timeouts