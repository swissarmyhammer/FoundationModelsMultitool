---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m545m9n7gyh0p1vmt6wxcd4w
  text: |-
    ### owner decision (2026-10-17), from ^t9dc8nb
    - ManualRunClock.waitForSleepers(atLeast:) in FoundationModelsExtras has no cancellation handler. In this repo, use the test-side wrapper waitForSleepers(atLeast:orUntil:) (Tests/FoundationModelsMultitoolTests/Support/ManualRunClockWaits.swift) at each call site in this group, with the end of the call as the second event. Groups 4 and 5 together hold 11 such call sites. Do not change Extras.
  timestamp: 2026-10-17T05:33:50.119779+00:00
- actor: claude-code
  id: 01m54hxmhmfe13vpkecve48b3j
  text: |-
    Research and implementation (in the tree, not committed):
    - Scope: the shell and child-process test files: ShellRunnerTests, ShellHistoryOpsTests, ShellSessionSweepTests, ShellExecuteTests, ShellCommandGateTests, ShellStateTests, BackgroundSettleGraceTests, OutputChunkStreamTests. StdioServerProcessTests was done in group 3 (it uses ensuring and withConnection). HardeningTests, MultiToolExecutionTests, SuspendedContextTests and RunCodeToolTimeoutTests are runCode waits and stay for group 5.
    - Discovery: a cancel of the task of ShellRunner.run stops the child (Subprocess ends the leader, and the teardown of the run kills the group). The run returns only after the reap. Thus cancel-then-await ends a run on each path. The old `defer { runTask.cancel() }` did not await the end, thus a child could stay unreaped after the test.
    - Discovery: ShellState.groupToCancel waits for a registration or a finalize also for a token that has no record yet, thus a canceler before the start of the run still ends.
    - New shared helper Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunTeardown.swift: endingShellRun(_:closing:after:). It closes the FIFO write end (when given), cancels the run and waits for its end (EventRace.endWait) on each path. A second close of a FileHandle does nothing (checked with a script). ShellRunnerTests (9 tests) and ShellHistoryOpsTests (2 tests) use it; the old `stop(_:)` copy is removed.
    - ShellRunnerTests.cancelerSendsNoKillAfterTheRunReapedItsChild: the hook opens a TestGate; EventRace.watch(_:untilOpen:orFail:) starts the canceler, and the wait for the hook also ends when the canceler ends.
    - BackgroundSettleGraceTests: 3 waitForSleepers sites now use callPastSettlePeriod(on:grace:timers:) (the wrapper waitForSleepers(atLeast:orUntil:) with the end of the call). defaultHostGetsTheInlineReport calls the wrapper with the end of the watched call. inlineResultOfFloatingCall: the wait for the end of the snippet code also ends when the call ends (EventRace.watch untilOpen).
    - ShellExecuteTests.callStopped(by:_:during:): the call is an EventRace.Watched; steps get it; the teardown awaits the end of the call after the stop on each path. The two step waits of outputGoesOutWhenItsCollectionIntervalEnds also end on the end of the call.
    - OutputChunkStreamTests.aCancelOfTheConsumerTaskEndsTheStream: the wait for the hook also ends when the consumer ends.
    - ShellCommandGateTests: new private withChild(_:arguments:input:_:) kills a test child with SIGKILL and waits for its exit when the body throws (4 children).
    - Counts: 24 cases fixed (fixtures 15: 9 ShellRunnerTests, 2 ShellHistoryOpsTests, 4 ShellCommandGateTests; waits 9: 5 BackgroundSettleGraceTests, 2 ShellExecuteTests, 1 ShellRunnerTests, 1 OutputChunkStreamTests). 59 sites already end on a second event (group 1 helpers: waitForStoredLines, SessionOutputLog, callPastSettlePeriod; the completion marker of the live view; ShellCommandGate releases; groupToCancel; 12 OutputChunkStreamTests reads after finish(), where the end of the stream came before the wait). waitForSleepers call sites moved to the wrapper: 4 (all in BackgroundSettleGraceTests). 6 sites stay for group 5: RunCodeToolTimeoutTests 4, SuspendedContextTests 1, and MCPServerCallTests.swift:605 (an MCP test, not shell or process; group 5 must decide). ^vg01093: 5 lines (8 sites).
    - Calls under test that end only on the kill under test (ShellRunnerTests runTask.value after clock.open, RoutedSession.close() in ShellSessionSweepTests) are not counted as waits: they are the call that the test examines.
    - Mutation check: in cancelerSendsNoKillAfterTheRunReapedItsChild the hook was not set (one time). swift test --filter on that test: exit 1, "failed after 0.045 seconds with 1 issue" (Expectation failed: hasArrived(), "the canceler ended before it came to the hook before its kill"). Before the change, `for await _ in entered {}` had no end. The mutation is reverted.
    - Test: swift build --build-tests, no error, no warning from source. swift test, one full run: exit code 0, "Test run with 2450 tests in 212 suites passed after 3.562 seconds". The only warning is the build-system line "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
  timestamp: 2026-10-17T09:08:39.092119+00:00
- actor: claude-code
  id: 01m54hy5am8g0dxygc40v9wdsz
  text: |-
    ### implement — changed
    - evidence: 7 test files changed, 1 new: Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunTeardown.swift (new), ShellRunnerTests.swift, ShellHistoryOpsTests.swift, BackgroundSettleGraceTests.swift, ShellExecuteTests.swift, ShellCommandGateTests.swift, OutputChunkStreamTests.swift. No production change. 24 cases fixed, 59 already end on a second event, 4 waitForSleepers call sites moved to the wrapper, 5 lines (8 sites) on ^vg01093. Mutation check: the canceler-hook test failed after 0.045 s, no hang, reverted. swift test, one full run: exit code 0, 2450 tests in 212 suites passed.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-17T09:08:56.276850+00:00
- actor: claude-code
  id: 01m54j0wgy3mknwwzb81ktk4np
  text: |-
    ### test - green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing summary: "Test run with 2450 tests in 212 suites passed after 4.632 seconds."
    - The run had 0 failures, 0 issues recorded, 0 skipped tests.
    - The only build warning came from the dependency mlx-swift (Cmlx): "missing creator for mutated node". It is not in this package.
    - No code changed in this step. No test was changed.
    - next: review.
  timestamp: 2026-10-17T09:10:25.566469+00:00
depends_on:
- 01M53W2YHNPEH570WMMC1V08M3
- 01M54D3FB8Q7J3PE3ZMBXXJDZ6
position_column: doing
position_ordinal: '8180'
title: 'T1 group 4: shell and child-process test waits with no second event'
---
Split from ^nvxckvr (test rule T1). The list (the shell and process waits in the unit tests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits. Fixtures close also when the test body throws.

Do: make each wait end on the first of two events: the expected event, or an existing end event (the child process exits, the pipe closes, the call ends). Make each child process end and be reaped on both paths. A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Show for at least one case that the test now fails (not hangs) when the expected event does not come (a one-time mutation that you revert). No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes #t1