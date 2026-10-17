---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m55e25xgm34q50b4kess4kjc
  text: 'Research done. ShellState is an actor, and its two stores are plain actor properties, not a Mutex. Thus the overload TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:) fits. Plan: lineCountWaiters becomes TestHookWaiters<Void, LineCountWaiter>, where LineCountWaiter now holds only the command id and the count (the detail). commandStartWaiters becomes TestHookWaiters<String?, String>, where the detail is the text. The resolve functions call resume(where:with:). Remove nextLineCountWaiterID, nextCommandStartWaiterID, endLineCountWait(commandID:id:), endCommandStartWait(id:) and the struct CommandStartWaiter. The store of the line waits is now flat (not keyed by command id); the detail holds the command id. The order in which the woken waits resume can change (dictionary order), but each selected wait still resumes one time. Tests that use the hooks: ShellRunnerTests, ShellHistoryOpsTests, BackgroundSettleGraceTests, Fixtures/ShellCommandGate. This is a refactor with no behavior change, thus the current tests are the guard; no new test.'
  timestamp: 2026-10-17T17:20:28.080058+00:00
- actor: claude-code
  id: 01m55e6387wp885se4jfgyqdqb
  text: |-
    ### implement — changed
    - evidence: ShellState.swift: lineCountWaiters is now TestHookWaiters<Void, StoredLinesTarget> (a flat store; the detail holds the command id and the count). commandStartWaiters is now TestHookWaiters<String?, String> (the detail is the text). waitForStoredLines(commandID:atLeast:) and waitForCommand(holding:) call TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:). resolveLineCountWaiters and resolveCommandStartWaiters call resume(where:with:). Removed: nextLineCountWaiterID, nextCommandStartWaiterID, endLineCountWait(commandID:id:), endCommandStartWait(id:), struct CommandStartWaiter, and the old LineCountWaiter (now StoredLinesTarget with no id and no continuation). TestHookWaiters.swift: the header comment now names ShellState too. The doc comments of both hooks still say that a cancel ends the wait. No test changed.
    - test: one run of swift test, exit code 0, "Test run with 2458 tests in 214 suites passed". SWIFT TASK CONTINUATION MISUSE lines: 0. The log has one build-system line "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle product; it is not from Swift source and not from this change. No compiler warnings.
    - next: review
  timestamp: 2026-10-17T17:22:36.423895+00:00
- actor: claude-code
  id: 01m55e9svxq6fs6590kr2shytg
  text: |-
    ### test — green
    - evidence: swift test ran one time. Exit code 0. Summary: "Test run with 2458 tests in 214 suites passed after 5.651 seconds." Lines with "SWIFT TASK CONTINUATION MISUSE": 0. Lines with "warning:": 0.
    - next: review.
  timestamp: 2026-10-17T17:24:37.885440+00:00
- actor: claude-code
  id: 01m55eavxve03fr06ahc1b7y7q
  text: |-
    ### commit — changed
    - evidence: local commit "refactor(shell): move the ShellState test-hook waits to the shared store". The sha is in the git log. Tests before commit: swift test, exit 0, 2458 passed, 0 failed, 0 skipped.
    - next: review
  timestamp: 2026-10-17T17:25:12.763152+00:00
- actor: claude-code
  id: 01m55egzvrfjphc0zdm4b6t5as
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit ab42c91). 0 findings, 0 confirmed, 0 refuted. 7 pairs attempted, 0 failed. The engine reviewed 2 files: ShellState.swift and TestHookWaiters.swift. The .reviewignore rule excluded the 4 .kanban files. The task has no prior findings sections.
    - next: The task is in done. No more work is necessary.
  timestamp: 2026-10-17T17:28:33.400452+00:00
- actor: claude-code
  id: 01m55ehkv66dwmsm917np3ttqx
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 source files (both ShellState waits on the shared TestHookWaiters store and TestHookWait.suspend overload; old counters, end functions and waiter structs removed)
    - test: green — swift test, exit 0, 2458 passed, 0 failed, 0 skipped, 0 continuation misuse lines
    - commit: ab42c91
    - review: clean — 0 findings
  timestamp: 2026-10-17T17:28:53.862212+00:00
position_column: done
position_ordinal: ffffffa380
title: Move the two ShellState test-hook waits to the shared TestHookWaiters store
---
Found during the review-finding work of ^cepemvm.

ShellState (Sources/FoundationModelsMultitool/Capabilities/Shell/ShellState.swift) has two waits that repeat the wiring that ^cepemvm removed from MCPServer: an id counter (nextCommandStartWaiterID, nextLineCountWaiterID), a dictionary store, and a TestHookWait.suspend call with a record closure and an end closure by id.

Do:
- Move each store to TestHookWaiters<Value, Detail> (Sources/FoundationModelsMultitool/Capabilities/TestHookWaiters.swift).
- Call TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:) from each wait. Delete the id counters and the copied record and end closures.
- Keep the behavior and every test the same.

Rule T1. No .timeLimit, sleep, poll or retry. Do not delete a test. One full run of swift test. #elicitation-fixes #t1