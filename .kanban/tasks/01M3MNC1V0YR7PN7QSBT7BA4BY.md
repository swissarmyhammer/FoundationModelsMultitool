---
assignees:
- claude-code
depends_on:
- 01M3MN9QX1TDARW8S19E390A6N
- 01M3MN9YSGJ8N3R97GFTY1RC0A
- 01M3MNAMK7626NA9DYJ4V9EG4P
- 01M3MNAWNW3PAZ1N3G1VF3PKVJ
- 01M3MNBF5PNAF9KFDZV77HYPT2
position_column: todo
position_ordinal: '8780'
title: 'OTel 8: add a content-safety test over the spans, log records and metrics of Multitool'
---
## What
The design (2026-09-28): each package has a content-safety test that uses the shared test helper from FoundationModelsExtras. A span attribute, a log message, a log metadata value and a metric dimension must never carry tool arguments, tool output, JS source, embed input text or MCP payloads. Router's `SpanContentSafetyTests` is the model: it drives real work against an in-memory tracer, reads every value, and fails on any value that has the fixture's own content.

**Upstream blocker (Extras board; it cannot be `depends_on` here):** Extras OTel B ^z6jqd9g (01M3MN8N9P4RPET2V5JZ6JQD9G), the content-safety helper in a new `TelemetryTestSupport` product. Do not start this task until it is on Extras `origin/main`.
- [ ] `Package.swift`: link the `TelemetryTestSupport` product to the unit test target only.
- [ ] `Tests/FoundationModelsMultitoolTests/TelemetryContentSafetyTests.swift` (new): with the Extras helper, drive work that uses unique marker strings as its content. The work must include:
  - a `runCode` call whose JS source, `tools.*` argument and return value each have a marker
  - a `searchTools` call with a marker in its intent
  - an MCP `tools/call` against `ScriptedServer` with markers in its arguments and result
  - a JS run that throws with a marker in the error text
  - a failed MCP call
- [ ] Assert that no recorded span attribute, span event, log message, log metadata value or metric dimension value has any marker.
- [ ] Add a line to the `MultitoolTelemetry` doc that names this test as the proof of the no-content rule, as `RouterTracing.swift` does.

## Acceptance Criteria
- [ ] The test fails if any one of the tasks OTel 2, 3, 4, 5 or 7 puts content into telemetry. Show this one time with a temporary bad attribute, then remove it.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/TelemetryContentSafetyTests.swift`, as described above.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #upstream-blocked #otel