---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12aceea5jwfqk7we20ah8wj
  text: |-
    ### Discoveries before the port

    - swift-sdk 0.12.1 `MCP.Client` does not resume a pending request when the transport drops. The message loop catches the stream error, logs it and stops. A `tools/call` in flight then waits forever. Only `client.disconnect()` and `client.cancelRequest(_:reason:)` resume a pending request. Thus the server must watch the transport itself: a `DropObservingTransport` in `Sources/.../MCP/` mirrors the receive stream of the transport the factory built, and it reports the end of that stream to `MCPServer.handleTransportDrop(generation:)`. The generation guard drops a report from a superseded connect. A drop the wrapper's own `disconnect()` caused is not reported: that is the host's disconnect.
    - `MCPServerError` becomes a `LostRunError` as a whole type. Swift has no per-case conformance. The call path throws only `.lost` from a run: a call on a server that is not `.ready` answers with an in-band `isError` result, and a bare-call timeout answers with an in-band `isError` result. The connect errors of the enum are thrown by host operations outside a run, so `ToolRun` never reads them.
    - `LiveCatalogTests.reconnectThroughRetainedFactoryEmitsOneSnapshot` requires exactly one snapshot for a scripted drop plus `reconnect()`. Thus a detected drop changes no `state` and emits no snapshot. It fails the in-flight calls as `.lost` and records the drop, and the host's `reconnect()` is the recovery.
    - The JS bridge of `MultiTool` turns an error a `tools.*` call throws into a promise rejection string, and `runSnippet` renders the failure as repairable text. A `LostRunError` would never reach `ToolRun`. A `LostRunRecord` per invocation notes the first `LostRunError` an inner call threw, and `runSnippet` throws it after the flush, before it renders. The outer background run then settles as `.lost`.
    - The request id is minted by the server (`ID.random`) and its string is the progress token, so one key finds the in-flight entry for a progress notification and for a cancel.
    - Test support: `CallCounter` stands in `Fixtures/AgentSessionFixtures.swift`; `TestPoll` in `Fixtures/PollFixtures.swift`; `RecordingEventSink` and `makeOuterRunContext` in `Fixtures/RunBindingFixtures.swift`; `backgroundRuns(over:)` in `Fixtures/SandboxGlobalsFixtures.swift`. A test-only `MCPCallProbeTool` stands in `Support/`, and both new suites read it.
    - No `.swift-format` or `.swiftlint.yml` stands in the repository. The new files follow the 4-space, 100-column style of the folder.
  timestamp: 2026-08-27T19:15:39.594545+00:00
- actor: claude-code
  id: 01m12bb9hdktmag4vvet2fvhe7
  text: |-
    ### implement — changed
    - evidence: 13 files. New: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift`, `Sources/FoundationModelsMultitool/Capabilities/MCP/DropObservingTransport.swift`, `Sources/FoundationModelsMultitool/Invocation/LostRunRecord.swift`, `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift`, `Tests/FoundationModelsMultitoolTests/LostCallTests.swift`, `Tests/FoundationModelsMultitoolTests/Support/MCPCallProbeTool.swift`. Changed: `MCPServer.swift`, `MCPServer+Connection.swift`, `MCPServer+ClientQueue.swift`, `BackoffPolicy.swift` (`MCPServerError: LostRunError`, new `.lost` case), `MCPCapability.swift`, `MultiTool.swift` (`LostRunRecord` rethrow after the snippet), `Tests/.../Support/MCPTestSupport.swift`, `Tests/.../Support/RespawningTransport.swift` (shared `servingFreshScriptedServers`). `swift build --build-tests`: no compiler warnings. `swift test --filter 'MCPServerCallTests|LostCallTests'`: 12 tests in 2 suites pass. All 10 checkboxes on the card are ticked.
    - next: `test` step, full `swift test`.
  timestamp: 2026-08-27T19:32:30.381497+00:00
depends_on:
- 01M112C9B7VKH4MEEVD832PG8R
- 01M1143Z8N0PH576EWD5EGQBJT
position_column: doing
position_ordinal: '80'
title: Rewrite MCPServer.call onto the run plane
---
## What
Give `MCPServer` one call method that runs to completion and speaks to the run plane through the ambient `ToolContext`. This replaces the sibling's `CallWait` / `CallDeadline` / `CallHandle` / `RunningCall` design and its follow-up tools. eventplan.md § "Consolidation of the siblings": "consolidation is promotion, not construction. One background engine goes in `ToolInvoker` plus the Router mailbox."

**Decision (recorded in the phase-4 note of eventplan.md by the first task).** An MCP verb is a plain synchronous `Tool`. It runs inside the run that called it, and eventplan.md § "The constraint boundary" states: "Inner `tools.*` calls run to completion." Thus `MCPServer.call` is `async throws`, it returns `CallTool.Result`, and it does not mint a `completionToken`. No `RunKind` case is added. The reason is the content plane: an MCP result has no store.

- File: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift`.
- `func call(name: String, arguments: [String: Value]?) async throws -> CallTool.Result`:
  - Capture `ToolContext.current` one time at the start (the capture-at-start rule of eventplan.md § "The ambient context"). Keep it in an in-flight table keyed by the request id, so the elicitation task can route a server request to the calling run. A `nil` context is a legal entry (the bare-session path).
  - Send `tools/call` with a `progressToken` in `_meta`. Route each `notifications/progress` for that token to `context?.progress(detail)`. The engine's `timeout` resets on progress; the server does not keep a clock of its own.
  - On `Task` cancellation: send `notifications/cancelled` for the request (advisory), and throw `CancellationError`. The engine reports the calling run as `.cancelled`.
  - On transport drop while the call is in flight: throw `MCPServerError.lost(...)`, and make `MCPServerError` conform to Router's `LostRunError` marker for that case (Router task `01M1142266PPAYQ22X4GHKGSSD`; stub `5egqbjt` here). Router's `ToolRun` then settles the calling background run as `.lost`. eventplan.md: "A transport drop is `.lost`."
  - A result with `isError: true` returns as a value. The renderer keeps it in band.
- Remove `defaultCallTimeout` from the server if the engine's `timeout` covers it. Keep it only for a call with no ambient context (a bare host call), and say so in the doc comment.

## Acceptance Criteria
- [x] A call against `ScriptedServer` returns the server's result.
- [x] A progress notification during a call reaches `ToolContext.progress`, and the test sink sees a `progress` event with the run's `correlationID`.
- [x] Cancellation of the calling `Task` sends `notifications/cancelled` to the server, and the call throws `CancellationError`.
- [x] A transport drop mid-call throws `MCPServerError.lost`, and that value is `any LostRunError`.
- [x] A background `runCode` run whose snippet awaits the call across a transport drop settles with `OperationOutcome.lost` in the mailbox.
- [x] `swift build` succeeds.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift` with the five criteria above. Bind a `ToolContext` with a recording sink around the call, the way `ShellExecuteTests.swift` does; the `.lost` settlement case runs the call inside a mounted `MultiTool` over a real `SessionMailbox`.
- [x] Port `LostCallTests.swift` and the progress cases of `OperationEventsTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/`, adapted to the ambient context. Drop the detach, `get_result`, and throttle cases; list them in the header.
- [x] `swift test --filter MCPServerCallTests` passes.
- [x] `swift test --filter LostCallTests` passes.

## Workflow
- Use `/tdd` — write the criteria as tests first, then implement the call. #eventplan #phase-4