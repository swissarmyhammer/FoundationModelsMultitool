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
depends_on:
- 01M53W2YHNPEH570WMMC1V08M3
position_column: todo
position_ordinal: '9580'
title: MCPServer.disconnect() does not drain the notifications/cancelled that a bare-call timeout sends
---
Found on ^c1v08m3 (T1 group 3).

A bare call (no ToolContext) that times out sends `notifications/cancelled` to the MCP server. CancellationNotices does not track this notice. Thus MCPServer.disconnect() does not wait for it, and the notice can be lost or arrive after the close. Because of this, the test wait at Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift about line 403 has no second event, and it is on the exception list ^vg01093.

Do (after the owner agrees that this is a product gap):
- Track the cancel notice of a bare-call timeout in CancellationNotices, the same way as the other cancel notices, so that disconnect() drains it.
- Start with a fixed-order test that fails on the current code. Then take the wait at MCPServerCallTests.swift about line 403 off ^vg01093 and give it the drain as its second event.
- Rule T1. No time limit, sleep, poll or retry. One full run. #elicitation-fixes