---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m545mbrfrmd069k73e0tr0tw
  text: |-
    ### owner decision (2026-10-17), from ^t9dc8nb
    - ManualRunClock.waitForSleepers(atLeast:) in FoundationModelsExtras has no cancellation handler. In this repo, use the test-side wrapper waitForSleepers(atLeast:orUntil:) (Tests/FoundationModelsMultitoolTests/Support/ManualRunClockWaits.swift) at each call site in this group, with the end of the call as the second event. Groups 4 and 5 together hold 11 such call sites. Do not change Extras.
  timestamp: 2026-10-17T05:33:52.271718+00:00
depends_on:
- 01M53W31F0R9FSZW7FV8Y8HTQX
position_column: todo
position_ordinal: '9380'
title: 'T1 group 5: JSC and runCode test waits with no second event'
---
Split from ^nvxckvr (test rule T1). The list (the JavaScriptCore sandbox and runCode waits in the unit tests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits.

Do: make each wait end on the first of two events: the expected event, or an existing end event (the run ends, the snippet promise settles, the call ends). A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Show for at least one case that the test now fails (not hangs) when the expected event does not come (a one-time mutation that you revert). No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes #t1