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
- actor: claude-code
  id: 01m3prqw0c13jx9gc4kpv1rfex
  text: |-
    Research (implement step):
    - The Extras checkout in .build and in IntegrationTests/.build is at 6c399a4. Package.resolved of both packages already pins 6c399a4. No package update is necessary.
    - The fork swift-sdk `Metadata` has `fields: [String: Value]` and `init(progressToken:additionalFields:)`. Thus `_meta` can carry `traceparent` and `tracestate`. No card for the swift-sdk board is necessary.
    - `TracedCall.run(_:ofKind:tracer:logger:attributes:metadata:_:)` takes a span kind. Thus the client span and the enter record use one call.
    - `Tracer.withSpan` sets the error status for a thrown error. A timeout of a bare call and an `isError` result do not throw. Thus the code must set the error status for these two.
    - The vocabulary test (`MultitoolTelemetryTests`) forbids two equal names over the span names, the attribute keys, the metric names and the log metadata keys. Thus the request id key moves from `LogMetadataKey` to `AttributeKey` (one reader, `MCPServer+Call.swift`).
    - A reconnect runs `disconnectClientWithoutHanging()` in `connect(via:)` (factory) and in `performConnectAttempt`. A transport drop goes through `handleTransportDrop(generation:)`. These are the places for the span events.
  timestamp: 2026-09-29T14:22:46.284487+00:00
- actor: claude-code
  id: 01m3ps7st7nbbeea9zftrbxak6
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` passes with no compiler warning (only the SwiftPM manifest-cache "disk I/O error" warnings and the mlx "missing creator" note of the toolchain). `swift test` (one run): 1846 tests in 150 suites passed, 0 failures. The new suite `MCPTracePropagation` has 6 tests, all pass. Before the implementation, `swift build --build-tests` failed on the new test (red).
    - files: Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+CallSpan.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Connection.swift, Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift, Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry+Tracing.swift, Tests/FoundationModelsMultitoolTests/MCPTracePropagationTests.swift (new), Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift, Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift, Tests/FoundationModelsMultitoolTests/Fixtures/LogReadbackFixtures.swift, Tests/FoundationModelsMultitoolTests/CallSpanTests.swift, Tests/FoundationModelsMultitoolTests/MultitoolTelemetryTests.swift.
    - what: `MCPServer.call` opens a client span (`FoundationModelsMultitool.mcp.call`, kind `.client`) through `MultitoolTelemetry.traced`, thus through `TracedCall.run`, which writes the enter record. `traced` now takes a span kind, a logger and enter metadata, and keeps an outcome that the body set. The span carries server name, tool name, request id, outcome, error kind, content count and content size (JSON bytes). No arguments and no result text. `InstrumentationSystem.instrument.inject` writes the trace context into the `_meta` next to `progressToken` (no second `traceparent` format). Error status for a thrown error (transport, cancel, JSON-RPC error), a bare-call timeout (`outcome=timedOut`, `error.kind=timeout`) and an `isError` result (`outcome=failed`, `error.kind=isError`). Span events `FoundationModelsMultitool.mcp.transport_dropped` (in `handleTransportDrop`) and `FoundationModelsMultitool.mcp.reconnect_started` (before each connect attempt) on each call in flight.
    - vocabulary: the request id key moved from `LogMetadataKey` to `AttributeKey` (same string). New `AttributeKey.contentCount`, `AttributeKey.contentBytes`, `OutcomeValue.failed`, `OutcomeValue.timedOut`, enum `ErrorKindValue`, enum `SpanEventName` (the vocabulary test now also checks the span event names).
    - note: a timeout under an engine context (`ToolMountError.timedOut`) reaches the MCP call as a cancel of the calling task, thus the span gets the error status and `outcome=cancelled` through `Tracer.withSpan`. The test covers the bare-call timeout, the one timeout that this file owns.
    - note: the swift-sdk fork `Metadata` has `fields` and `additionalFields`, thus no card for the swift-sdk board.
    - next: review.
  timestamp: 2026-09-29T14:31:28.327245+00:00
- actor: claude-code
  id: 01m3psgy4zce2w5xzbbdj3m31q
  text: |-
    ### test — green
    - evidence: I touched the changed Swift files. Then `swift build --build-tests` completed with 0 compiler warnings from this package. `swift test` ran 1846 tests in 150 suites: all passed, 0 failed, 0 skipped. XCTest ran 0 tests. `swift build --package-path IntegrationTests --build-tests` completed with 0 compiler warnings and 0 errors. The only other messages were the known SwiftPM "disk I/O error" manifest-cache messages and the "missing creator for mutated node ... mlx-swift_Cmlx.bundle" message. These do not come from this package.
    - next: review
  timestamp: 2026-09-29T14:36:27.679617+00:00
- actor: claude-code
  id: 01m3pt17qd2tvtfyr17nj79cn5
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 5f5109b). 0 findings, 0 confirmed, 3 refuted. 11 files reviewed. 4 files in .kanban/ not reviewed (excluded by .reviewignore). The task has no earlier Review Findings sections.
    - next: none. The task is in done.
  timestamp: 2026-09-29T14:45:21.773241+00:00
- actor: claude-code
  id: 01m3pt1kxyy5j5xmft8gkx53hb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 11 files (MCP client span in new MCPServer+CallSpan.swift; traceparent in _meta through the tracer inject; new MCPTracePropagationTests.swift)
    - test: green — swift test 1846 tests in 150 suites passed (one run); IntegrationTests build passed
    - commit: 5f5109b
    - review: clean — 0 findings
  timestamp: 2026-09-29T14:45:34.270390+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
- 01M3MN9YSGJ8N3R97GFTY1RC0A
position_column: done
position_ordinal: ffff80
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