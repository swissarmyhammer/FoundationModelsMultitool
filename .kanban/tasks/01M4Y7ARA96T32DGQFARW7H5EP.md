---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: 'Possible defect: a queued MCP connect can run beside a disconnect after the 500 ms bound'
---
Found in mail step 5, T3, 2026-10-14, while the ResilienceTests hang was examined.

In the MCPServer client-operation queue, a connect that waits behind a disconnect proceeds when the disconnect bound (`clientDisconnectGracePeriod`, 500 ms on `clientQueueClock`) ends. The comment in MCPServer+ClientQueue.swift says that `client.disconnect()` changes its state at its start. In the current swift-sdk, `Client.disconnect()` does an `await` (the logger read) before it takes the state. Thus, after the bound, the late disconnect can close the connection of the new connect. The new connect then fails, its retry sends `initialize` on a disconnected in-memory transport, and the request stays pending.

The test hang (bad test, fixed in the test with GatedClock.openRecordedSleeps) came from this order. The product code is not changed. Decision needed: fix the queue (for example, do not let a connect pass a disconnect that has not ended), or accept the 500 ms window.

#mail-step-5 #defect