---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41w01fyhvjp7hhjcqtn8d13
  text: |-
    Research:
    - The swift-sdk `Server` starts each request handler in its own `Task`. Thus the handler counter of the hanging tool is not an ordered point: a probe call can answer before the handler of an earlier re-sent request starts.
    - `MCPServer.dispatch` returns from `client.send(request)` when the request is on the wire. It does not wait for the answer.
    - `WireRecordingTransport` (test support) records each message that the client sends, by JSON-RPC method, in one ordered ledger, and takes test markers. It wraps any transport, thus it can wrap `RespawningTransport`; its `connectWrapped()` caches the new receive stream on each connect, thus it works across a reconnect.
    - Plan: connect over `WireRecordingTransport(wrapping: respawning)`. After the lost call throws, put a marker in the ledger. Reconnect. Then make one probe call (echo) on the same connection and wait for its answer. Assert that the ledger after the marker holds exactly one `tools/call` (the probe). A re-send that the library makes before its next call stands before the probe in the ledger. No clock.
  timestamp: 2026-10-03T21:51:18.526538+00:00
- actor: claude-code
  id: 01m41w89t8t0k7b2np0f1383m6
  text: |-
    Implementation:
    - `LostCallTests.swift`: removed `autoRetryGraceWindow` and the `Task.sleep`. The test now connects over `WireRecordingTransport(wrapping: respawning)`, and each fresh scripted server also serves the echo tool. After the lost call throws, the test puts the marker "reconnect starts" in the ledger, reconnects, and makes one echo probe call on the same connection. It asserts that the ledger holds exactly one `tools/call` after the marker (the probe). New helper `callsSent(after:on:)`, new constants `reconnectMarker`, `callEntry`, `oneCallAfterReconnect`. The old `counter.count == oneInvocation` assertion stays as a second check, but the doc comment says why it is not the ordered proof.
    - The synchronization point is the probe: the client sends the probe after the reconnect returns. A re-send that the reconnect makes goes on the wire before the probe, and the ledger records each send in order. No clock in the test and no change to library code.
    - Server-side order (the card's first idea) is not ordered: the swift-sdk `Server` starts each request handler in its own `Task`, thus a record in the handler can come after the probe answer. The client-side send ledger is the ordered point.
    - Mutation proof (reverted): for one run, `failInFlightCalls` recorded the tool name of each lost call, and `reconnect()` re-sent a `tools/call` for each name after the connect. `swift test --filter LostCallTests`: 1 of 2 failed, 2 issues: `callsAfterReconnect` was 2 (expected 1), the ledger showed two `tools/call` after the marker; `counter.count` was 2. After the revert, `git diff --stat` shows no change under `Sources/`.
    - Limit: a re-send that the library defers to after its next call (for example a detached task that runs later) is not ordered before the probe. The 300 ms sleep did not prove that case either.
    - `swift build --build-tests` prints one SwiftPM line `warning: missing creator for mutated node: (...mlx-swift_Cmlx.bundle/Contents/MacOS)`. It comes from the build graph of the mlx resource bundle, not from a source file, and it is not from this change.
  timestamp: 2026-10-03T21:55:49.192297+00:00
- actor: claude-code
  id: 01m41w8f0t3h653vkvvsha87c6
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/LostCallTests.swift. `swift build --build-tests` complete. `swift test --filter LostCallTests`: 2 of 2 passed. Mutation run (library re-sends the lost call on reconnect, reverted): 1 of 2 failed, `callsAfterReconnect` 2 (expected 1). `swift test`: 1808 tests in 151 suites passed. No change under Sources/.
    - next: /review
  timestamp: 2026-10-03T21:55:54.522366+00:00
position_column: doing
position_ordinal: '80'
title: LostCallTests no-auto-retry case waits 300 ms to learn that no retry came
---
## What
`LostCallTests.noAutoRetryAfterReconnectEvenForIdempotentHintedTool` reconnects the server, then sleeps for `autoRetryGraceWindow` (300 ms), and then asserts that the handler of the hanging tool ran one time only. The sleep is a deadline that the test waits for to learn that an event (a re-sent call) did not come. The rule of ^fafvwrc is: no test waits for a deadline to learn that an event did not come.

Found during ^fafvwrc. That card changed only the `guard` of this test to an `#expect`. It did not change the sleep, because the card is about the four tests that read an inner terminal.

Subtasks:
- [x] Find a synchronization point that proves that no call is re-sent after the reconnect, with no sleep. One possible point: after the reconnect, make one more call on the same connection and read the order of the requests that the new scripted server recorded. If no such point is possible without a clock, record why on this card and ask the user.

## Acceptance Criteria
- [x] The no-auto-retry test has no sleep and no deadline that it waits for to learn that a retry did not come.
- [x] The test still fails when a change re-sends a `lost` call after the reconnect.

## Tests
- [x] `swift test --filter LostCallTests` passes. `swift test` passes. #defect #timeouts