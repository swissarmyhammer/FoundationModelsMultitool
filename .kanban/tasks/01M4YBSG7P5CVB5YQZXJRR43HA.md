---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zbxdc8yf17wj38tr1mfkx2
  text: 'The 5 s bound (`clientConnectStragglerGracePeriod`, `pendingConnectStragglers`) is gone. Cause of the bound: one `MCP.Client` was used for each connect attempt, thus a retry had to wait for a straggler that was still inside `client.connect(transport:)`. Now each connect attempt makes its own `MCP.Client`. A straggler changes only its own client, the generation guard discards its late result, and it tears its own client down. Thus no attempt waits for another attempt, and no clock decides the order. The client queue file `MCPServer+ClientQueue.swift` is removed. Proof: `ResilienceTests.aStragglerThatEndsAfterTheRetryLeavesTheConnectionOfTheRetry` fails on the old code (the retry waits behind the straggler on the queue clock: recorded sleep [5.0 seconds]) and passes with the change.'
  timestamp: 2026-10-15T08:47:28.136707+00:00
position_column: done
position_ordinal: fffff180
title: Remove the 5 s time bound behind a connect that has not ended
---
The MCP client queue lets a later operation pass a connect that has not ended after `clientConnectStragglerGracePeriod` (5 s). This is a time bound in product code. Replace it with an event, as the fix in 7808212 did for the disconnect turn. Do not start before the owner gives the order. #mail-step-5 #defect