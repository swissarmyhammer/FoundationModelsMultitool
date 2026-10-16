---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51y1x2a9mw8whq7xzmabcmw
  text: |-
    Research and fix.

    - `MCP.Client.disconnect()` (swift-sdk) does: take the loop task, resume pending requests, cancel the loop task, `disconnect()` the transport, then await the loop task. Only the last step can hang (a suspended server-to-client handler). So `endAttempts(before:)` does not await the whole teardown. It waits for the first of: the teardown returned, or the transport closed. Each event comes after the cancel of the loop.
    - The close event uses a new `closeObservers` list on `OpenTransport`, not `closeWaiters`. Reason: the test hook `waitUntilTransportCloseIsAwaited()` reads `closeWaiters`, and `ResilienceTests.disconnectEndsAStragglerWhoseConnectNeverReturns` must still see the teardown return first.
    - The teardown task is stored on the attempt (`clientTeardown`), so `dropAttemptClient` and `endAttempts` share one `client.disconnect()` call. A second call on the client returns at once (no task, no connection) and would not prove that the cancel came.
    - (i) still matters after (ii): a client whose `connect(transport:)` did not start has no loop at the stop; it can start its loop after the stop, before the direct disconnect.
    - No test for (ii): the cancel of the loop task is private to `MCP.Client`. The signs of it at the transport (the end of the mirror iteration) come on other tasks with no fixed order to the close call. A check would need a wait that can fail to come, or a race.

    Proof: RED (old code) `aDisconnectEndsEachReceiveStreamWithAnError` failed two checks at DropObservingTransportTests.swift:130 and :134 ("an error was expected but none was thrown"), no hang. GREEN: passed.
  timestamp: 2026-10-16T08:42:58.506963+00:00
position_column: done
position_ordinal: fffffe80
title: The MCP client loop can spin after a host disconnect
---
`MCPServer.disconnect()` starts the teardown of the client in a task that it does not wait for. Then `endAttempts(before:)` calls `disconnect()` on the `DropObservingTransport` directly. The wrapper records the disconnect, and `end(_:after:)` ends the mirror with no error. The message loop of `MCP.Client` reads a normal end, calls `receive()` again, gets the same ended mirror, and spins until its task is cancelled.

Fix:
- [x] After a disconnect of the wrapper, end the mirror with a named "disconnected" error (`DropObservingTransport.Disconnected`). A host disconnect is still not reported as a drop.
- [x] `receive()` after the end returns a stream that throws the same error.
- [x] Update the header and doc comments: every end of the mirror throws.
- [x] `endAttempts(before:)` stops the loop of the client of an attempt before the direct disconnect of its transport (`stopClientLoop(ofAttempt:)`: wait for the first of "the teardown of the client returned" and "the transport closed"). The guarantees of `disconnect()` stay.
- [x] Test (fixed order): `receive()`, `disconnect()`, read to the end, second `receive()`, read. Each read throws.

#bug