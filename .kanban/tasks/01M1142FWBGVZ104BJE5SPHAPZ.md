---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11xtffv7s69h7xdk2ajevdg
  text: |-
    ### research — done
    - `HTTPClientTransport.init(endpoint:configuration:...)` builds its own `URLSession` from the configuration. POST sends `Accept: application/json, text/event-stream`, `Content-Type: application/json`, `MCP-Protocol-Version`, `MCP-Session-Id`. GET sends `Accept: text/event-stream`, `Cache-Control`, `MCP-Protocol-Version`, `MCP-Session-Id`.
    - `StatefulHTTPServerTransport.handleRequest(_:)` answers a POST request with `.stream`, a notification with `.accepted`, a GET with `.stream`. A server-initiated request (`elicitation/create`) goes to the standalone GET stream only. A message sent before the GET stream is open is stored, and is not replayed to a new GET without `Last-Event-ID`. So a test must wait for the GET stream before it calls an eliciting tool. `LoopbackHTTPServer.isServingEventStream` gives that reading.
    - `OriginValidator.localhost()` reads `Host` and `Origin` only when the request carries them. A `URLRequest` handed to a `URLProtocol` carries neither, so the default strict pipeline stays.
    - A `URLProtocol` gets `httpBody` as `nil` and the body as `httpBodyStream`. The join reads the stream.
    - `Mutex` from `Synchronization` is the lock the package already uses (`SingleResume`, `StdioServerProcess`). The `URLProtocol` registry uses it, because `canInit(with:)` is synchronous.
    - No formatter config file is in the repo (`.swift-format`, `.swiftformat` absent).
  timestamp: 2026-08-27T15:36:07.931573+00:00
- actor: claude-code
  id: 01m11xyr2n8570xnnkrrs6psrh
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/Support/MCPTestServer/LoopbackHTTPServer.swift (new), Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift (new), Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift (`.http` case). `swift build --build-tests`: no error, no warning in the changed files. `swift test --filter LoopbackHTTPServerTests`: 4 tests, 5 cases, all pass.
    - The headers relayed verbatim through the `URLProtocol` satisfy the default strict pipeline, so no permissive pipeline was needed.
    - The `URLProtocol` gets the request body as `httpBodyStream`, not `httpBody`; the join reads the stream. A test that needs a server-initiated message waits on `LoopbackHTTPServer.isServingEventStream` first, because the server transport stores, and does not replay, a message sent before the GET stream is open.
    - next: /test, then /commit, then /review
  timestamp: 2026-08-27T15:38:27.797801+00:00
- actor: claude-code
  id: 01m11zhd8h10jfr5v8bzvgjyt9
  text: |-
    ### test — green
    - evidence: `swift test` — 1220 tests in 89 suites passed, 0 failed, 0 skipped, 0 warnings. LoopbackHTTPServer suite green. Confirmed over three consecutive full runs.
    - Found under the full parallel run: the two SSE tests (tools/list_changed, elicitation) that hold a live `HTTPClientTransport` GET SSE stream over `URLSession` failed only when many suites ran concurrently. `swift test --no-parallel` and `--filter LoopbackHTTPServer` (4 parallel) both passed; a 200-plus-test concurrent subset reproduced it. Cause: four concurrent loopback SSE streams, whose client read runs on the shared cooperative thread pool, tip the pool past a threshold where a server-to-client message stalls and never arrives. Raising timeouts did not help (proved not mere slowness) and was reverted.
    - Fix: the platform-native `.serialized` trait on the suite, so one loopback SSE stream is open at a time. This is a serialization trait, not an environment switch; every test still runs on every `swift test`. Reasoning is documented on the suite.
    - next: /commit
  timestamp: 2026-08-27T16:06:07.889576+00:00
depends_on:
- 01M112BHBVEYK3ZZH0RGQRTXXY
position_column: doing
position_ordinal: '80'
title: In-process HTTP loopback for the MCP test server
---
## What
Give the scripted test server a third transport: an in-process HTTP loopback, so the MCP suites run each case over HTTP as well as in memory. Both halves are in swift-sdk 0.12.1; this task writes only the join.

- Add `Tests/Support/MCPTestServer/LoopbackHTTPServer.swift` to the `MCPTestServer` product. It serves one `ScriptedServer` through the sdk's `StatefulHTTPServerTransport` (`public func handleRequest(_ request: HTTPRequest) async -> HTTPResponse`; the sdk's own `HTTPRequest` / `HTTPResponse`, body inline, SSE as `.stream(AsyncThrowingStream<Data, Error>)`; no `HTTPTypes`, no swift-nio).
- **The join is a `URLProtocol` subclass, not a socket.** `HTTPClientTransport.init(endpoint:configuration:streaming:sseInitializationTimeout:protocolVersion:authorizer:requestModifier:logger:)` takes a `URLSessionConfiguration` and builds its own `URLSession` from it. Register the subclass in `configuration.protocolClasses`, and route each request to `handleRequest`. Expose `LoopbackHTTPServer.start() -> (endpoint: URL, configuration: URLSessionConfiguration)` and `stop()`.
- **Validation pipeline.** `StatefulHTTPServerTransport()`'s default pipeline is strict: `OriginValidator.localhost()`, `AcceptHeaderValidator(mode: .sseRequired)`, `ContentTypeValidator`, `ProtocolVersionValidator`, `SessionValidator`. The client sends `Accept: application/json, text/event-stream`, a `Content-Type`, and `MCP-Protocol-Version`; the loopback must relay those headers verbatim. If a header is dropped by the `URLProtocol` path, pass a permissive `StandardValidationPipeline(validators:)` to the transport and say so in the doc comment.
- Add `connectedServer(over: .http)` to `Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift` beside `.inMemory`, so one parameterized case runs over both.

## Acceptance Criteria
- [x] An `MCP.Client` over `HTTPClientTransport(endpoint:configuration:)` at the loopback completes `initialize`, `tools/list`, and a `tools/call` of `echo` in one process, with no socket.
- [x] A server-initiated `elicitation/create` from `elicitEcho` reaches the client's elicitation handler over the loopback, and the answer returns to the tool.
- [x] `notifications/tools/list_changed` reaches the client over the loopback SSE stream.
- [x] `swift build` succeeds.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/LoopbackHTTPServerTests.swift` with the criteria above, with a bare `MCP.Client` built with `Client.Capabilities.Elicitation(form: .init(), url: .init())` and a handler from `Client.withElicitationHandler(_:)`.
- [x] `swift test --filter LoopbackHTTPServerTests` passes.

## Workflow
- Use `/tdd` — write the loopback tests first, then the `URLProtocol` join. #eventplan #phase-4