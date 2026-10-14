---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: 'Bad test: ResilienceTests hung one time (a wait that never resumes)'
---
Found in mail step 5, T3, 2026-10-14.

`swift test --skip-build --filter ResilienceTests` hung for 31 minutes one time. A sample of the test helper (PID 31590) showed only idle threads, so a suspended task waited on an event that never came. The next run of the same suite passed (13 tests). The output of the hung run was lost, so the test is not known.

Candidates: a lost wake-up in the new internal MCPServer waiter hooks, a gate or a gated transport that misses an early open, or `server.disconnect()` that waits on `clientDisconnectGracePeriod` on a never-opened GatedClock while a server-to-client handler is suspended.

Find the cause by reading code, and make the tests deterministic. Do not run the suite again and again.

Sample: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer-FoundationModelsMultitool/31c4648d-e774-4650-80ab-60edb9eb2fe5/scratchpad/resilience-hang.sample.txt

#mail-step-5 #bug