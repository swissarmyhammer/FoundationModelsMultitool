---
assignees:
- claude-code
depends_on:
- 01M112BHBVEYK3ZZH0RGQRTXXY
position_column: todo
position_ordinal: '9580'
title: In-process HTTP loopback for the MCP test server
---
## What
Give the scripted test server a third transport: an in-process HTTP loopback, so the MCP suites run each case over HTTP as well as in memory. Both halves are in swift-sdk 0.12.1; this task writes only the join.

- Add `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift` to the `MCPTestServer` product. It serves one `ScriptedServer` through the sdk's `StatefulHTTPServerTransport` (`public func handleRequest(_ request: HTTPRequest) async -> HTTPResponse`; the sdk's own `HTTPRequest` / `HTTPResponse`, body inline, SSE as `.stream(AsyncThrowingStream<Data, Error>)`; no `HTTPTypes`, no swift-nio).
- **The join is a `URLProtocol` subclass, not a socket.** `HTTPClientTransport.init(endpoint:configuration:streaming:sseInitializationTimeout:protocolVersion:authorizer:requestModifier:logger:)` takes a `URLSessionConfiguration` and builds its own `URLSession` from it. Register the subclass in `configuration.protocolClasses`, and route each request to `handleRequest`. Expose `LoopbackHTTPServer.start() -> (endpoint: URL, configuration: URLSessionConfiguration)` and `stop()`.
- **Validation pipeline.** `StatefulHTTPServerTransport()`'s default pipeline is strict: `OriginValidator.localhost()`, `AcceptHeaderValidator(mode: .sseRequired)`, `ContentTypeValidator`, `ProtocolVersionValidator`, `SessionValidator`. The client sends `Accept: application/json, text/event-stream`, a `Content-Type`, and `MCP-Protocol-Version`; the loopback must relay those headers verbatim. If a header is dropped by the `URLProtocol` path, pass a permissive `StandardValidationPipeline(validators:)` to the transport and say so in the doc comment.
- Add `connectedServer(over: .http)` to `Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift` beside `.inMemory`, so one parameterized case runs over both.

## Acceptance Criteria
- [ ] An `MCP.Client` over `HTTPClientTransport(endpoint:configuration:)` at the loopback completes `initialize`, `tools/list`, and a `tools/call` of `echo` in one process, with no socket.
- [ ] A server-initiated `elicitation/create` from `elicitEcho` reaches the client's elicitation handler over the loopback, and the answer returns to the tool.
- [ ] `notifications/tools/list_changed` reaches the client over the loopback SSE stream.
- [ ] `swift build` succeeds.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift` with the criteria above, with a bare `MCP.Client` built with `Client.Capabilities.Elicitation(form: .init(), url: .init())` and a handler from `Client.withElicitationHandler(_:)`.
- [ ] `swift test --filter LoopbackHTTPServerTests` passes.

## Workflow
- Use `/tdd` — write the loopback tests first, then the `URLProtocol` join. #eventplan #phase-4