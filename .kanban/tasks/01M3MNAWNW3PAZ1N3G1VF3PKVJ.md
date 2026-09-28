---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnc4s3pt7nzet3868bqmsm
  text: 'Upstream helper id (from the swissarmyhammer session, 2026-09-28): the enter log record for a long MCP call uses Extras OTel C ^ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA). The client span and the traceparent injection do not need it. If Extras OTel C is not on origin/main when this task starts, do the span and the injection, and write a follow-up card for the enter record.'
  timestamp: 2026-09-28T18:45:27.459986+00:00
- actor: claude-code
  id: 01m3mv2meqn5f3fknwc8zf1q0z
  text: 'Upstream blocker (from the swissarmyhammer session, 2026-09-28): Extras OTel E ^wts388b (01M3MV1R3D52RAMFNFKWTS388B), not implemented yet. `TelemetryCapture` now uses `InMemoryTracer`, which does not inject W3C `traceparent`, so a test in a capture cannot check the `traceparent` in the MCP request `_meta`. OTel E makes `TelemetryCapture` bind a tracer that injects and extracts `traceparent` and `tracestate`. Do not start this task until OTel E is on Extras origin/main, or write the propagation test with its own injecting test tracer and without `TelemetryCapture`.'
  timestamp: 2026-09-28T20:25:07.287806+00:00
- actor: claude-code
  id: 01m3mwcdxdwhnr1n05dewftyaa
  text: 'Update (2026-09-28, swissarmyhammer session): Extras OTel E ^wts388b is on Extras origin/main (6c399a4). No Extras blocker is left. Run `swift package update FoundationModelsExtras` (root and IntegrationTests) first. Inject through the tracer''s `inject` (`InstrumentationSystem.instrument.inject` / the bound tracer) with the field names in `ExtrasTelemetry` (`traceparent`, `tracestate`). Do NOT write a second `traceparent` format. In tests, `TelemetryCapture.Context.tracer` is a `W3CInMemoryTracer` that injects and extracts these fields; `SpanIdentity` is public.'
  timestamp: 2026-09-28T20:47:56.845752+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
- 01M3MN9YSGJ8N3R97GFTY1RC0A
position_column: todo
position_ordinal: '8480'
title: 'OTel 5: open a client span for each MCP server call, and inject W3C traceparent into the MCP request _meta'
---
## What
The design (2026-09-28): trace context crosses process boundaries as W3C `traceparent` and `tracestate` in the MCP request `_meta`. Each MCP server call gets a client span. Span attributes carry no MCP payload, tool arguments or tool output.

The MCP call is sent in `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift:180-186`: the request is built with `meta: Metadata(progressToken: .string(requestID...))` and sent with `client.send(request)`. The MCP sdk is the fork `swissarmyhammer/swift-sdk` (see `Package.swift`, `mcpPackage`).
- [ ] Open a client span (`SpanKind.client`) around each `tools/call` request, with the name and keys from `MultitoolTelemetry`: server name, MCP tool name, request id, outcome, result content count and size. If the call can wait for a long time (for example a slow tool or an elicitation), also write the enter log record through the same Extras helper as OTel 4, when that helper exists. Until then, only the span.
- [ ] Inject the span's context as W3C `traceparent` and, if present, `tracestate` into the request `_meta`, next to `progressToken`, through `InstrumentationSystem.instrument.inject` with an injector for the sdk's `Metadata`. If the sdk's `Metadata` cannot carry extra fields, stop, and write the card text for the swift-sdk fork (see memory `cross-repo-cards-go-on-their-board`).
- [ ] Set the span status to error for a transport error, a timeout (`ToolMountError.timedOut`), a cancel and an `isError` result.
- [ ] Record a span event, not a new span, for a reconnect or a server restart during the call.

## Acceptance Criteria
- [ ] Each MCP `tools/call` has one client span that is a child of the current span (for example the `tools.*` dispatch span).
- [ ] The request that reaches the server has `_meta.traceparent` with the trace id and span id of that client span.
- [ ] No span attribute has the request arguments or the result text of the fixture.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MCPTracePropagationTests.swift` (new), against `ScriptedServer` with a recording transport and an in-memory tracer: the recorded request `_meta` has a valid `traceparent` (`00-<32 hex>-<16 hex>-<2 hex>`) that matches the client span.
- [ ] The same suite: a hanging call that times out, and a tool that returns `isError`, give an error status.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass. #otel