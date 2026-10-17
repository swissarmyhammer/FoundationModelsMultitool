---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Move the two ShellState test-hook waits to the shared TestHookWaiters store
---
Found during the review-finding work of ^cepemvm.

ShellState (Sources/FoundationModelsMultitool/Capabilities/Shell/ShellState.swift) has two waits that repeat the wiring that ^cepemvm removed from MCPServer: an id counter (nextCommandStartWaiterID, nextLineCountWaiterID), a dictionary store, and a TestHookWait.suspend call with a record closure and an end closure by id.

Do:
- Move each store to TestHookWaiters<Value, Detail> (Sources/FoundationModelsMultitool/Capabilities/TestHookWaiters.swift).
- Call TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:) from each wait. Delete the id counters and the copied record and end closures.
- Keep the behavior and every test the same.

Rule T1. No .timeLimit, sleep, poll or retry. Do not delete a test. One full run of swift test. #elicitation-fixes #t1