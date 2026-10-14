---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4yazx5ah3wsxqx512d2eppz
  text: |-
    Cause: `MCP.Client.disconnect()` of the swift-sdk does `await logger?.debug(...)` (it reads `connection?.logger`) before it takes its connection, its message-handling task and its pending requests. The client-operation queue let the next operation pass a disconnect when the 500 ms bound (`clientDisconnectGracePeriod`) ended. Thus a connect could run before a late disconnect took the state, and the late disconnect then took and closed the new connection.

    Fix (Multitool only, no swift-sdk change): a disconnect operation ends its queue turn at the first of two events: (1) the client calls `disconnect()` on the `DropObservingTransport` that it took, which reports the call to `MCPServer.endClientDisconnectTurn()`; (2) `client.disconnect()` returns (the client had nothing to take). No clock decides this order. The 500 ms bound is removed. The wait behind an unresolved connect keeps its 5 s bound. The caller of `disconnectClientWithoutHanging()` waits until the transport that the client took closed (the report closure that `endClientDisconnectTurn()` gives back), or until `client.disconnect()` returned. A suspended server-to-client handler blocks only the wait for the message-handling task, which comes after the transport closed, thus neither the queue nor the caller hangs.

    Test: `ResilienceTests.queuedConnectNeverPassesADisconnectThatDidNotTakeTheClientState` (new `ScopeHeldClock` test clock, `GatedDisconnectTransport.disconnectArrival`). On the old code it fails: `listTools()` throws "Client connection not initialized". With the fix it passes. The old test of the 500 ms bound is now `freshOperationPassesAnInFlightDisconnectThatTookTheClientState`: it checks that a fresh connect passes a disconnect that took the state and does not return, with no bound recorded. Filtered MCP run: 145 tests in 15 suites passed. Full `swift test`: 2379 tests in 209 suites passed.
  timestamp: 2026-10-14T23:12:06.826896+00:00
position_column: done
position_ordinal: ffffe580
title: 'Possible defect: a queued MCP connect can run beside a disconnect after the 500 ms bound'
---
Found in mail step 5, T3, 2026-10-14, while the ResilienceTests hang was examined.

In the MCPServer client-operation queue, a connect that waits behind a disconnect proceeds when the disconnect bound (`clientDisconnectGracePeriod`, 500 ms on `clientQueueClock`) ends. The comment in MCPServer+ClientQueue.swift says that `client.disconnect()` changes its state at its start. In the current swift-sdk, `Client.disconnect()` does an `await` (the logger read) before it takes the state. Thus, after the bound, the late disconnect can close the connection of the new connect. The new connect then fails, its retry sends `initialize` on a disconnected in-memory transport, and the request stays pending.

The test hang (bad test, fixed in the test with GatedClock.openRecordedSleeps) came from this order. The product code is not changed. Decision needed: fix the queue (for example, do not let a connect pass a disconnect that has not ended), or accept the 500 ms window.

#mail-step-5 #defect