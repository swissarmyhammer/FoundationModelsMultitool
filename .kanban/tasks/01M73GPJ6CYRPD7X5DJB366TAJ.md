---
assignees:
- claude-code
position_column: todo
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
- [ ] `connect(via:)` over a stdio server `/bin/sh -c "exit 0"` throws, and the state is `.faulted`.
- [ ] The same for `read line; exit 0` (the server reads `initialize`, then exits).
- [ ] A drop after `.ready` does not change the state (no change to the behavior).

## Tests
- [ ] New test file Tests/FoundationModelsMultitoolTests/MCPHandshakeDropTests.swift. No clock: the test waits for the connect to end.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #bug