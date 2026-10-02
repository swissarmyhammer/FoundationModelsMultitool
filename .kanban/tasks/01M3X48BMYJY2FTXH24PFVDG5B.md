---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: Remove the remaining short real-time windows from root tests
---
## What
The search of ^kdtrmhv found more tests that need a real-time window to hold. Each needs a production seam or a new event, so ^kdtrmhv did not change them. The user decision is: "no test checks the speed of the machine".

- `MultiToolExecutionTests.sandboxWaitIsRemovedAndTheRunComesBackAsOneMail`: `shortInlineSettleGrace` (1 s). The gated snippet must outlast it, and the second snippet must settle in it.
- `CLIAnswerDrainTests`: `unreachedTimeLimitSeconds` (30 s). `CLIMailWait` has no clock seam.
- `LoopbackHTTPServer.requestTimeout` (30 s). Its doc is stale.
- `RegisteredJournalOpTests`: a 600 ms in-flight window.
- `ScriptedServerSelfTests.cancelledNotificationRecording`: a 50 ms lead.
- The windows in `MCPServerCallTests` and `MCPSessionSweepTests`.
- `LiveCatalogTests.coalescesRapidBurstIntoOneRelist`.

A lower bound (`elapsed >= X`) cannot fail on a slow machine. It is not in this list.

## Do
- For each item: wait for an event, or inject a clock (add the seam where none exists).

## Acceptance Criteria
- [ ] Each item above waits for an event or uses an injected clock.

## Tests
- [ ] Root `swift test` passes once.