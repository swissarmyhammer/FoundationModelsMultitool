---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Pass a gated connect-attempt clock through the MCPTestSupport connect helpers
---
## What
`MCPServer.connectAttemptClock` exists (^tm4x2hp). But `MCPTestSupport.connectedMCPServer(...)` and the helpers that `StdioServerProcessTests` use do not pass it. Thus each connect in these tests races a real 10 s per-attempt timeout. A slow machine can make the connect time out. That is a check of the speed of the machine (decision on ^tm4x2hp and ^kdtrmhv).

## Do
- Give the helpers a `connectAttemptClock` parameter. The default for a test is a clock that does not end (`GatedClock`, as `ResilienceTests.makeServer` does in ^kdtrmhv).
- A test of the timeout gives its own clock, and opens it only after the gated step is in flight (`connectWasCalled` / `makeWasCalled`, added in ^kdtrmhv).

## Acceptance Criteria
- [ ] No root test connect depends on the real 10 s connect timeout.

## Tests
- [ ] Root `swift test` passes once.