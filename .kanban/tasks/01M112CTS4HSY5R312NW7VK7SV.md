---
assignees:
- claude-code
depends_on:
- 01M112C9B7VKH4MEEVD832PG8R
- 01M1143Z8N0PH576EWD5EGQBJT
position_column: todo
position_ordinal: '8880'
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
- [ ] A call against `ScriptedServer` returns the server's result.
- [ ] A progress notification during a call reaches `ToolContext.progress`, and the test sink sees a `progress` event with the run's `correlationID`.
- [ ] Cancellation of the calling `Task` sends `notifications/cancelled` to the server, and the call throws `CancellationError`.
- [ ] A transport drop mid-call throws `MCPServerError.lost`, and that value is `any LostRunError`.
- [ ] A background `runCode` run whose snippet awaits the call across a transport drop settles with `OperationOutcome.lost` in the mailbox.
- [ ] `swift build` succeeds.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift` with the five criteria above. Bind a `ToolContext` with a recording sink around the call, the way `ShellExecuteTests.swift` does; the `.lost` settlement case runs the call inside a mounted `MultiTool` over a real `SessionMailbox`.
- [ ] Port `LostCallTests.swift` and the progress cases of `OperationEventsTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/`, adapted to the ambient context. Drop the detach, `get_result`, and throttle cases; list them in the header.
- [ ] `swift test --filter MCPServerCallTests` passes.
- [ ] `swift test --filter LostCallTests` passes.

## Workflow
- Use `/tdd` — write the criteria as tests first, then implement the call. #eventplan #phase-4