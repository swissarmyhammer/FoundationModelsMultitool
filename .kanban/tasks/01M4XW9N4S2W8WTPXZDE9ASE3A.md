---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xxgt70v93ts6bpvhqapzmd
  text: 'Decision G1 (owner, T0): no Router change. Use `@testable import FoundationModelsRouter` and call the internal Router.useRunClock(_:), as ACPAgent does in Support/ManualClockProfile.swift. If this does not work for the stub Router session of StubRouterFixtures, tell the owner why. Count: 53 .timeLimit traits; also remove TestHangGuard and IntegrationHangGuard.'
  timestamp: 2026-10-14T19:16:40.800529+00:00
- actor: claude-code
  id: 01m4xz8w2mk07jsyrpbjsggyn7
  text: |-
    Owner decisions for T3 (2026-10-14):
    1. LoopbackHTTPServer: no time bound (timeoutInterval .infinity). Delete TestHangGuard.
    2. Fix MCPServer+Call.swift startBareTimeout to sleep on the injected clock, as its own commit with the defect task ^7cbsd5 (01M4XZ6QQJ14B7J7JF987CBSD5). Tests use the manual clock. Add a fixed-order test that fails on the old code.
    3. OS state: a kqueue process-exit source for each known pid. Check before the wait with kill ESRCH or the SZOMB status (see ACPAgent ProcessExitWatch.hasExited), because a zombie stays until its parent reaps it.
    4. LiveSearchSpacing stays as a rate rule of an external service, not a test wait. Write that in its doc comment.
    5. Small internal waiter hooks in Multitool Sources, reached with @testable import, no public API change.
    6. The delayed-echo tool waits on a gate that the runner opens after the first answer ended.
    Rule: replace a sleep in a JSC host function with a gate, not with Task.yield.
  timestamp: 2026-10-14T19:47:17.716108+00:00
depends_on:
- 01M4XW9AT79H485N08AS57YT6F
position_column: done
position_ordinal: ffffe380
title: 'Mail step 5 T3: remove each .timeLimit, sleep, clock wait and poll from Tests and IntegrationTests'
---
Step 5 of the mail work. Read mailbox.md (sections 3, 4 and 5, the signals table, section 8 rows 2 to 5, and the Progress table). All items in mailbox.md are decisions. This task starts after T2.

## Work
- Remove the 83 .timeLimit traits from Tests and IntegrationTests.
- Remove each sleep, clock wait and poll from Tests and IntegrationTests.
- Replace each one with one of these:
  - a wait on an event,
  - a gate,
  - a fixed order,
  - ManualRunClock (through RunPlane(clock:)) for a run timeout or a settle deadline,
  - TelemetryCapture.Context.wait(until:) for telemetry.
- A clock can stay only to measure and print elapsed time, never to wait.

## Rules
- Write all text (comments, docs, commits, reports, tasks) in STE.
- Commit after the task, with Multitool green. Report to the step 5 owner: the commit, the test result, and each difference from the plan with its reason. Do not push until the owner accepts step 5.
- Run the full suite one time. Do not run tests again and again to find a failure. A test that fails only sometimes is a bad test: find the cause and make it deterministic, or fix the race in the code. Do not use .timeLimit, sleep, clock wait, poll or retry. If a test hangs, take `sample <pid>` of your own test process before you stop it. Stop only your own process ids.
- Ask the owner before a decision that is not in the plan. Do not delete a test without the decision of the owner.

#mail-step-5