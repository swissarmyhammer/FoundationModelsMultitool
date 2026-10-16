---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51y2crq5h62rhdp52a9kbp4
  text: |-
    Proof and product behavior.

    - RED: the temporary fixed-order check (old order: bound fires before the call reaches `MCPServer.call`) failed at `#expect(await scripted.recordedNotifications.count == 1)` after 0.084 s, with no hang. `inFlightCalls` stayed empty. The file was deleted after the run.
    - GREEN: the fixed test passed (0.026 s).
    - Product behavior: when the bound fires before the call is in flight, `callInSpan` throws at `Task.checkCancellation()`. No `tools/call` request goes out, thus no `notifications/cancelled` goes out, and no entry stays in `inFlightCalls`. This is correct: a request that was never sent has nothing to cancel on the wire. It is not a product defect. No product code changed for this card.
  timestamp: 2026-10-16T08:43:14.583281+00:00
position_column: done
position_ordinal: ffffff80
title: 'Bad test: the inner-call bound can fire before the MCP call reaches the server (MCPServerCallTests)'
---
`MCPServerCallTests` "a call under a context to a server that makes no progress ends at the inner-call bound" waited only for the sleeper of the mount timer, then moved the `ManualRunClock`. Under load the timer can sleep before the request is in `inFlightCalls`. Then the move fires the timer, the mount cancels the call before `callInSpan` installs its cancel handler, `Task.checkCancellation()` throws, no request and no `notifications/cancelled` go out, and `waitForRecordedNotifications(count: 1)` waits for ever.

Fix:
- [x] The hanging tool opens an arrival gate (`hangingTool(arrival:)`). The test moves the clock only after the arrival and the sleeper.
- [x] Each wait of the test is for an event that the test made occur first. The test comment states the argument for each wait.
- [x] Proof of the old order with a fixed-order check (temporary test, not committed): a probe waits on a gate before `server.call`; the clock moves; the mount gives `.timedOut`; the gate opens; the probe ends; `recordedNotifications.count == 1` fails with no wait.

#bad-test