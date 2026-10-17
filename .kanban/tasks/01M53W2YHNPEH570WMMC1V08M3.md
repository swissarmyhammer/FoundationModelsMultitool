---
assignees:
- claude-code
depends_on:
- 01M53W2TYXASHFQ2PZV6MHKP5E
position_column: todo
position_ordinal: '9180'
title: 'T1 group 3: MCP test waits with no second event'
---
Split from ^nvxckvr (test rule T1). The list (the waits in the MCP test files other than MCPElicitationTests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits.

Do: make each wait end on the first of two events: the expected event, or an existing end event (the call ends, the transport closes, the stream finishes). A wait for a notification can nearly always also end on the close of its transport or the end of its call. Use the shared FirstEvent helper (from ^nvxckvr) where it fits. A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Show for at least one case that the test now fails (not hangs) when the expected event does not come (a one-time mutation that you revert). No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes #t1