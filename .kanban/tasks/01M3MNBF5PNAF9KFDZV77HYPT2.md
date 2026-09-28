---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtxer1xgfmz3jgyf0f3mfw
  text: 'Fact from the swissarmyhammer session (2026-09-28): Extras already records `FoundationModelsExtras.tool.calls` and `FoundationModelsExtras.tool.duration` for each mounted tool call, with only the dimensions `tool.name` and `tool.outcome`. So do not record a second count and duration for `runCode` and `searchTools` here. Check whether the inner `tools.*` dispatch (`RunBinding.invoke`, through `RunBinding.innerCallMount`) already goes through the Extras tool hosting and gets these metrics. Record Multitool metrics only where Extras does not: the MCP server errors and restarts, the JS interpreter run duration, and the inner dispatch if Extras does not count it. Also: a metric made before the first `TelemetryCapture` does not go to the capture, so make metrics per call or per instance, not in a `static let` that a test touches first. Extras OTel A–D are not on Extras origin/main yet (2026-09-28).'
  timestamp: 2026-09-28T20:22:17.601269+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: todo
position_ordinal: '8680'
title: 'OTel 7: add swift-metrics metrics for tool calls, MCP server errors and restarts, and JS interpreter runs'
---
## What
The design (2026-09-28): libraries use the `swift-metrics` API. A metric dimension carries no content: tool names, server names, verbs and outcomes are safe, and arguments, JS source and output are not. Take the metric names and dimension keys from `MultitoolTelemetry` (task OTel 1).
- [ ] **Tool calls:** a `Counter` and a `Timer` for each call to `runCode` (`MultiTool.call`), `searchTools` (`SearchToolsTool.call`) and each inner `tools.*` dispatch (`RunBinding.invoke`). Dimensions: the tool name (`runCode`, `searchTools`, or the `noun.verb` of the inner tool) and the outcome (`succeeded`, `failed`, `cancelled`, `timedOut`, `pending`).
- [ ] **MCP servers:** a `Counter` for call errors by server name and error kind (transport, timeout, `isError`, protocol), and a `Counter` for restarts or reconnects by server name. The sites are in `Capabilities/MCP/MCPServer+Call.swift`, `MCPServer+Connection.swift` and `StdioServerProcess.swift` (respawn).
- [ ] **JS interpreter:** a `Timer` for each JS interpreter run (`Interpreter/JSCInterpreter.swift` `run`), with the outcome as a dimension (completed, threw, time limit, cancelled).
- [ ] Keep the number of dimension values low: do not use a request id or a completion token as a dimension.

## Acceptance Criteria
- [ ] Each metric above is recorded with the correct name and dimensions for one call of each kind.
- [ ] No dimension value has content from the fixture (arguments, JS source, output).
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MetricsTests.swift` (new), with an in-memory metrics factory (`MetricsTestKit` from swift-metrics): one `runCode` call that calls one `tools.*` verb records the counter and the timer for both tools with the correct outcome.
- [ ] The same suite: an MCP call to a failing `ScriptedServer` records the error counter. A respawn records the restart counter. A JS run that throws records the timer with `threw`.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.