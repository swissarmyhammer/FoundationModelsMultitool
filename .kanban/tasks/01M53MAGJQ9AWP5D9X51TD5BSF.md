---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m547f1he4amtx74ex8mjtc4w
  text: |-
    ### review — clean
    - evidence: The work of this card is in commit 56d94af. `waitUntilTransportCloseIsAwaited()` calls `TestHookWait.suspend(on:cancelValue:resolvedValue:record:end:)`. Its own copy of the scaffold is removed. `endTransportCloseAwaitedWait(_:)` is the `end` step of the helper. `review sha 56d94af~1..56d94af`: 0 findings, 0 confirmed, 1 refuted. 0 findings in MCPServer+ClientLifecycle.swift and TestHookWait.swift. The earlier full run on 56d94af: swift test exit 0, 2449 passed.
    - next: none. The card is in done.
  timestamp: 2026-10-17T06:05:55.118939+00:00
- actor: claude-code
  id: 01m547fwd8tka8esfr474bdm69
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — the work came in 56d94af (card ^t9dc8nb): waitUntilTransportCloseIsAwaited calls TestHookWait.suspend; its own scaffold is removed
    - test: green — swift test, exit 0, 2449 passed (the run on 56d94af)
    - commit: 56d94af
    - review: clean — 0 findings in MCPServer+ClientLifecycle.swift and TestHookWait.swift
  timestamp: 2026-10-17T06:06:22.632799+00:00
position_column: done
position_ordinal: ffffff9680
title: Use the generic test-hook wait scaffold for waitUntilTransportCloseIsAwaited
---
`waitUntilTransportCloseIsAwaited()` and `endTransportCloseAwaitedWait(_:)` in Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+ClientLifecycle.swift have the same scaffold that ^zjdtdfj removed from MCPServer+Elicitation.swift: a continuation under a wait id in a dictionary, withTaskCancellationHandler + withCheckedContinuation, and a Task on cancel that calls an end function.

^zjdtdfj added `suspendTestHookWait` (private, in MCPServer+Elicitation.swift) and the value type `ElicitationWaiters<Value>` (ElicitationWaiters.swift). The transport-close wait has no elicitation id, so the shared type and the scaffold need a small change to serve it: for example, move the scaffold to a file of its own, make it internal, and make the waiter type generic over its key.

Keep the behaviour and the tests the same. No new time limit, sleep, poll or retry. One full `swift test` run. #elicitation-fixes