---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Use the generic test-hook wait scaffold for waitUntilTransportCloseIsAwaited
---
`waitUntilTransportCloseIsAwaited()` and `endTransportCloseAwaitedWait(_:)` in Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+ClientLifecycle.swift have the same scaffold that ^zjdtdfj removed from MCPServer+Elicitation.swift: a continuation under a wait id in a dictionary, withTaskCancellationHandler + withCheckedContinuation, and a Task on cancel that calls an end function.

^zjdtdfj added `suspendTestHookWait` (private, in MCPServer+Elicitation.swift) and the value type `ElicitationWaiters<Value>` (ElicitationWaiters.swift). The transport-close wait has no elicitation id, so the shared type and the scaffold need a small change to serve it: for example, move the scaffold to a file of its own, make it internal, and make the waiter type generic over its key.

Keep the behaviour and the tests the same. No new time limit, sleep, poll or retry. One full `swift test` run. #elicitation-fixes