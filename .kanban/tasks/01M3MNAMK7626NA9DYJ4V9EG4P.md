---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnc25x007nsrq8e0wzn3z4
  text: 'Upstream blocker id (from the swissarmyhammer session, 2026-09-28): Extras OTel C ^ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA), the span-plus-"enter"-log helper that replaces CallTrace. Do not start this task until it is on Extras origin/main.'
  timestamp: 2026-09-28T18:45:24.797805+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
- 01M3MN9QX1TDARW8S19E390A6N
position_column: todo
position_ordinal: '8380'
title: 'OTel 4: replace CallTrace with real spans and an enter log record, and keep the hang diagnosis'
---
## What
`Sources/FoundationModelsMultitool/Diagnostics/CallTrace.swift` (181 lines) writes an `enter`/`exit` pair to the unified log through `os.Logger` and `OSSignposter` (subsystem `com.swissarmyhammer.multitool`). The last `enter` with no `exit` names a call that hangs. It is used at four points:
- `MultiTool.call` (`MultiTool.swift:379`, `trace` / `noAmbientToken`)
- `SearchToolsTool.call` (`Discovery/SearchToolsTool.swift:71`)
- the `tools.*` dispatch in `RunBinding.invoke` (`Invocation/RunBinding.swift:77`)
- `TracedAgentSession` (`Discovery/TracedAgentSession.swift:35`)

The design (2026-09-28): use real `swift-distributed-tracing` spans and remove `OSSignposter` and `os.Logger`. An OpenTelemetry span is exported only when it ends, and a call that hangs never ends. So a span on a call that can suspend for a long time also writes ONE "enter" log record when it starts, and log records are exported at once. FoundationModelsExtras supplies a helper for this.

**Upstream blocker (Extras board; it cannot be `depends_on` here):** the Extras task that supplies the span-with-enter-record helper. Its card id is not known on 2026-09-28. Ask the swissarmyhammer session for it. Do not start this task until that helper is on Extras `origin/main`.
- [ ] At each of the four points, open a span with the name from `MultitoolTelemetry` through the Extras helper, which writes the enter log record. Attributes: tool name, verb/op/noun, outcome, counts and sizes only, never arguments, JS source or output. Set the span status to error when the call throws.
- [ ] Nest the spans in the current `ServiceContext`, so that an inner `tools.*` span is a child of the `runCode` span, and the `runCode` span is a child of the Router tool-call span when a session calls it.
- [ ] Delete `CallTrace.swift` and the `CallTrace` types. Move its "why this exists" and "reading a trace" doc into `MultitoolTelemetry` or the helper doc, and rewrite it for OTLP: the last enter record with no ended span names the hung call.

## Acceptance Criteria
- [ ] `rg -n 'CallTrace|OSSignposter|os\.Logger' Sources/FoundationModelsMultitool` returns no match.
- [ ] Each of the four points gives one span and one enter log record for each call. A call that does not return leaves its enter record and no ended span.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CallSpanTests.swift` (new), with an in-memory tracer (`InMemoryTracer` from swift-distributed-tracing, or the Extras test support) and the in-memory log handler of OTel 2: a `runCode` call that calls one `tools.*` verb gives a `runCode` span with one child span, and two enter records.
- [ ] The same suite: a `tools.*` call that never returns (a gated tool) gives an enter record and no ended span for that call, and the parent is still open.
- [ ] The same suite: a thrown error sets the error status on the span.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #upstream-blocked #otel