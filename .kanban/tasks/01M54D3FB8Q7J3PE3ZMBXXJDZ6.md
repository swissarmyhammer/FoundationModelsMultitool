---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m54d4mr8jjxefwtr6379yvbs
  text: |-
    ### decision — owner (2026-10-17)
    - Yes, fix it. Order: after the commit of T1 group 3 (^c1v08m3), before T1 groups 4-7.
    - Why: a cancel notice that disconnect loses is an R2/R3 gap (an end must not get lost before the feed ends). It is a small production change in Multitool only.
    - Fix: CancellationNotices also tracks the notifications/cancelled that a bare-call timeout sends, and MCPServer.disconnect() drains it as it drains the ToolContext ones.
    - Test: a deterministic test that a bare-call timeout followed at once by disconnect() delivers the notice (RED on the current code). Then the wait at MCPServerCallTests.swift about line 403 ends on that event, and its line is removed from ^vg01093.
    - Push: in the same batch as group 3 if group 3 is not pushed yet; else in the next batch with group 4.
  timestamp: 2026-10-17T07:45:05.800966+00:00
- actor: claude-code
  id: 01m54fw9p0mzbtq16eq23d4p7c
  text: |-
    Research (implement step):
    - The bare-call timer is in MCPServer+Call.swift startBareTimeout. After the clock sleep it calls endInFlightCall directly in the timer task. endInFlightCall settles the call first (the caller resumes and can call disconnect at once), and only then sends notifications/cancelled. No record goes into CancellationNotices, thus disconnect() drains nothing for it.
    - Second fact: settleInFlightCall cancels entry.bareTimeout. In the timeout path that task is the timer task itself. Thus the send of the cancel notice runs in a cancelled task. A transport whose send obeys task cancellation (HTTPClientTransport sends through URLSession, which stops on a cancel) then fails the send at all times, and the notice is lost also with no disconnect.
    - The wait for the old test (aBareCallIsBoundedByTheCallTimeout) is now at MCPServerCallTests.swift line 433, not 403. It is a direct call of scripted.waitForRecordedNotifications, not inside waitForNotifications(of:count:sentBy:).
    - A test that only calls disconnect() at once after the call cannot fail on the current code in a fixed order: the in-memory send does not check cancellation, and the timer send usually wins the race. A hold on the send cannot make it fixed-order without a production hook, because the fixed code shows no event while the hold stays closed.
    - Plan: RED test connects through a small test transport whose send throws CancellationError when the sending task is cancelled. On the current code the timer task is cancelled, thus the notice fails in a fixed order. The fix tracks the notice in CancellationNotices from the timer task, before the settlement: the tracked task is a new task (not cancelled), and disconnect() drains it.
  timestamp: 2026-10-17T08:32:58.048470+00:00
- actor: claude-code
  id: 01m54g5e65xgbf6m8wmvtyf5c0
  text: |-
    ### implement — changed
    - evidence: RED then GREEN, then one full run.
    - Production: Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift — startBareTimeout now calls cancellationNotices.track before the settlement; the new isolated method endTimedOutBareCall(requestID:) ends the call and sends the notice. Doc updates in CancellationNotices.swift and MCPServer.swift.
    - Tests: new test aBareCallTimeoutThenDisconnectDeliversTheCancelNotice in Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift, with the new double Tests/FoundationModelsMultitoolTests/Support/CancellationHonoringTransport.swift (its send throws CancellationError from a cancelled task, as HTTPClientTransport over URLSession does). MCPTestSupport.closingOnFailure is now internal (was private) for the new connect helper. aBareCallIsBoundedByTheCallTimeout now waits through expectOneCancelledNotification (disconnect drain, then the wait that also ends on the end of the message loop). Doc line in MCPConnectionScope.swift.
    - RED: the new test failed in a fixed order on the old code: recorded.first?.method was nil. The log showed the cancel notice send failed with CancellationError, because the settlement cancels the timer task that sends.
    - GREEN: the new test passed after the fix.
    - Full run: swift test, exit code 0, "Test run with 2450 tests in 212 suites passed". One build-system line: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle path; it comes from the build graph, not from source.
    - Exception list: comment on ^vg01093 removes the line MCPServerCallTests.swift:403 waitForRecordedNotifications.
    - Limit: the RED fails because of the cancelled sender. A change that sends from a new task with no tracking would make this test pass in most runs but not in a fixed order; no fixed-order test of the drain alone exists without a production hook.
    - next: review.
  timestamp: 2026-10-17T08:37:57.573911+00:00
- actor: claude-code
  id: 01m54g8754yf2ysbcqj33a1r5b
  text: |-
    ### test - green
    - command: swift test (exit code 0)
    - result: Test run with 2450 tests in 212 suites passed after 3.165 seconds. 0 failures, 0 skipped tests.
    - warning: one build-tool line, "missing creator for mutated node", for the mlx-swift_Cmlx.bundle dependency. It does not come from this package source.
    - next: review
  timestamp: 2026-10-17T08:39:28.676993+00:00
- actor: claude-code
  id: 01m54g9b8z2rjx3e5x5c9endwy
  text: |-
    ### commit — changed
    - evidence: f3922f5 fix(mcp): drain the cancel notice of a bare-call timeout on disconnect
    - next: review
  timestamp: 2026-10-17T08:40:05.663640+00:00
- actor: claude-code
  id: 01m54gf022qbyge3bfsk7mfssf
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 206beac). 0 findings, 0 confirmed, 0 refuted. 7 files reviewed. 6 files in .kanban/ are not reviewed because of the ignore rule.
    - next: The task is in done. No work remains on this card.
  timestamp: 2026-10-17T08:43:10.786995+00:00
- actor: claude-code
  id: 01m54gfqhertnh87p85x6qpjav
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (the bare-call cancel notice is tracked in CancellationNotices and drained by disconnect(); the notice is no longer sent from a cancelled task)
    - test: green — swift test, exit 0, 2450 passed, 0 failed, 0 skipped
    - commit: 206beac (the commit comment names f3922f5, the sha before the amend)
    - review: clean — 0 findings
  timestamp: 2026-10-17T08:43:34.830664+00:00
depends_on:
- 01M53W2YHNPEH570WMMC1V08M3
position_column: done
position_ordinal: ffffff9980
title: MCPServer.disconnect() does not drain the notifications/cancelled that a bare-call timeout sends
---
Found on ^c1v08m3 (T1 group 3).

A bare call (no ToolContext) that times out sends `notifications/cancelled` to the MCP server. CancellationNotices does not track this notice. Thus MCPServer.disconnect() does not wait for it, and the notice can be lost or arrive after the close. Because of this, the test wait at Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift about line 403 has no second event, and it is on the exception list ^vg01093.

Do (after the owner agrees that this is a product gap):
- Track the cancel notice of a bare-call timeout in CancellationNotices, the same way as the other cancel notices, so that disconnect() drains it.
- Start with a fixed-order test that fails on the current code. Then take the wait at MCPServerCallTests.swift about line 403 off ^vg01093 and give it the drain as its second event.
- Rule T1. No time limit, sleep, poll or retry. One full run. #elicitation-fixes