---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y7e2j85gd0gbz19rn34w2j
  text: 'Fixed in 60df8af. Cause: freshOperationWaitsForInFlightDisconnectStragglerBoundedByDisconnectGracePeriod called queueClock.open(), which also ended later bounds. A connect and a disconnect then ran together on one MCP.Client; the late disconnect closed the new connection; the retry sent initialize on a disconnected in-memory transport; the attempt timeout slept on a never-opened GatedClock, so the wait stayed forever. Fix: GatedClock.openRecordedSleeps() ends only the recorded bounds; the test waits for the 7 recorded bounds first, so the order is fixed. One run of the suite: 13 tests pass. The product window is recorded as task 01M4Y7ARA96T32DGQFARW7H5EP.'
  timestamp: 2026-10-14T22:09:56.808060+00:00
position_column: done
position_ordinal: ffffe280
title: 'Bad test: ResilienceTests hung one time (a wait that never resumes)'
---
Found in mail step 5, T3, 2026-10-14.

`swift test --skip-build --filter ResilienceTests` hung for 31 minutes one time. A sample of the test helper (PID 31590) showed only idle threads, so a suspended task waited on an event that never came. The next run of the same suite passed (13 tests). The output of the hung run was lost, so the test is not known.

Candidates: a lost wake-up in the new internal MCPServer waiter hooks, a gate or a gated transport that misses an early open, or `server.disconnect()` that waits on `clientDisconnectGracePeriod` on a never-opened GatedClock while a server-to-client handler is suspended.

Find the cause by reading code, and make the tests deterministic. Do not run the suite again and again.

Sample: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsMultitool/31c4648d-e774-4650-80ab-60edb9eb2fe5/scratchpad/resilience-hang.sample.txt

#mail-step-5 #bug