---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m73h6cdhz53m03r8q0f42sm8
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (03382f97): 1 finding (1 confirmed, 2 refuted) — Tests/FoundationModelsMultitoolTests/MCPHandshakeDropTests.swift:71
    - next: Add a test where the server answers `initialize`, then exits before it answers `tools/list`. Make sure that `connect(via:)` throws and the state is `.faulted`. Use no clock.
  timestamp: 2026-11-10T20:08:06.321092+00:00
position_column: review
position_ordinal: '80'
title: MCP connect waits with no end when the stdio server exits before it answers initialize
---
## What
Report from ACPAgent (card 01M7388MV2SHFEHA7QQXJT257A). A stdio server that exits before it answers `initialize` makes `MCPServer.connect(via:)` wait with no end. The state stays `.connecting`.

Cause:
1. `applyConnect(via:generation:)` in Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Connection.swift waits on `MCP.Client.connect(transport:)`. The SDK client ends the wait for `initialize` only on `disconnect()` or a cancel.
2. `handleTransportDrop(generation:)` in MCPServer+Call.swift fails only the open tool calls. It does not end the connect attempt.

Fix:
- `DropObservingTransport` gives the transport id of the attempt to `handleTransportDrop(generation:transportID:)`.
- When the state is `.connecting` (handshake or discovery of the current attempt), the drop tears down the client of that attempt. Thus the wait ends with an error.
- `applyConnect` then throws `MCPError.connectionClosed` and moves the state to `.faulted`.
- `DropObservingTransport.send(_:)` throws after a drop or a disconnect, thus a request that the client registers after the teardown also fails.

## Acceptance Criteria
- [x] `connect(via:)` over a stdio server `/bin/sh -c "exit 0"` throws, and the state is `.faulted`.
- [x] The same for `read line; exit 0` (the server reads `initialize`, then exits).
- [x] A drop after `.ready` does not change the state (no change to the behavior).

## Tests
- [x] New test file Tests/FoundationModelsMultitoolTests/MCPHandshakeDropTests.swift. No clock: the test waits for the connect to end.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #bug

## Review Findings (2026-11-10 14:06)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/MCPHandshakeDropTests.swift:71` `completeness/invariant-propagation` — The fix tears down the client on a drop during the whole handshake, which the source comment says covers both `initialize` and `tools/list`. The suite exercises only the `initialize` case. All three scripts (`exit 0`, `read line; exit 0`, `read line; exit 1`) end the server before it answers anything. No test drops the server after it answers `initialize` and before discovery ends. The `tools/list` branch of the fix is therefore unproven, and a regression there would not be caught. Add one script that answers `initialize` (a fixed JSON-RPC result line), then reads the next line and exits with no answer. Assert that `connect(via:)` throws and the state is `.faulted`. Keep the test event-driven, with no clock.