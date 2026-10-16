---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51pb8eswz9951w8mm47jy50
  text: |-
    Fix set A is done (one card for each hazard, all in done):
    - ^wg9mxhv (bad-test): waitUntilZombie runs waitid on a dedicated thread (DedicatedThread.run).
    - ^wwyejbg (bad-test): the kill test does not change SIGPIPE; new test theRequestPipeOfTheChildRaisesNoSIGPIPE reads F_GETNOSIGPIPE on the request descriptor of the child.
    - ^f24szhz (bug): FileWalker git ls-files uses Subprocess.run, discards stderr, waits through an event. New tests for a 128 KiB stderr and for a failed listing.
    - ^78b1m9y (bad-test): runGit, processIDs(matching:) and catFixtureChunks use Subprocess.run and are async.
    - ^17n8417 (bug): StdioServerProcess reaps the child (killpg + waitpid) on a dedicated thread on shutdown, respawn, disconnect and dispose.
    Follow-up in todo: ^n9kan94 (bug) deinit of ProcessState still reaps synchronously.
    Finding f: no test waits on real time (runSnippet calls multiTool.call directly, no settle timer; MCPServerCallTests:447 uses ManualRunClock).
    The cause of the freeze is still not proven. The card stays in review until a CI run is green.
  timestamp: 2026-10-16T06:28:16.473946+00:00
- actor: claude-code
  id: 01m51sd4zbdd7ttwqn7dvxsx7n
  text: |-
    CI run 38861563159 (head 57ab995, fix set A) froze again. "Run tests" started 07:09:39Z. The test output stopped at 07:10:11.62Z (2572 of 2579 tests and suites ended, no issue recorded). The watcher cancelled the run at 07:19:47Z (more than 600 s). No rerun.
    Open tests (exact name match, log fixA-ci.log):
    - MCPServerCallTests.swift:447 "a call under a context to a server that makes no progress ends at the inner-call bound" (started 07:10:07.088)
    - OverBudgetSelectionOrderTests.swift:120 "an id the model answers twice is spliced one time" (started 07:10:11.619)
    - MCPElicitationTests.swift:535 "decline and cancel reach the server as those actions, and neither cancels the run" (started 07:10:11.621)
    Open suites: MCPServerCallTests, MCPElicitationTests, OverBudgetSelectionOrderTests.
    FileChangeEventAbsenceTests:168 and StdioServerProcessTests:432 ended this time; in run 38843335879 they were open. The three tests above were open in both runs. Thus fix set A did not remove the freeze. The next work is to find what these three tests wait on.
  timestamp: 2026-10-16T07:21:44.171005+00:00
- actor: claude-code
  id: 01m51y2hbk7bsgapdsvvstxh4m
  text: |-
    Two fixes for the open tests of CI 38843335879, MCPServerCallTests.swift:447 among them. This card stays in doing until CI is green.

    - Defect A (product, #bug): after a host disconnect, `DropObservingTransport` ended the mirror with no error, and each later `receive()` gave the same ended stream. The swift-sdk client loop then spun until its task was cancelled, on a pool thread. Fix: every end of the mirror throws (`DropObservingTransport.Disconnected` after a disconnect), a `receive()` after the end gives a stream that throws, and `endAttempts(before:)` stops the client loop (waits for the first of "the client teardown returned" and "the transport closed") before it closes the transport itself.
    - Defect B (test, #bad-test): the inner-call bound test moved the `ManualRunClock` before the request was in flight. Then no `notifications/cancelled` went out and `waitForRecordedNotifications(count: 1)` waited for ever. Fix: the hanging tool opens an arrival gate, and the test moves the clock only after the arrival.
  timestamp: 2026-10-16T08:43:19.283668+00:00
position_column: doing
position_ordinal: '80'
title: CI test process froze near the end of the run (CI 38843335879), and synchronous waits run on the cooperative pool
---
CI run 38843335879 (head c620900): `swift test` wrote no output for 2 h after 3.4 s, and was cancelled. 5 tests were open: MCPServerCallTests.swift:447, FileChangeEventAbsenceTests.swift:168, OverBudgetSelectionOrderTests.swift:120, StdioServerProcessTests.swift:432, MCPElicitationTests.swift:535. A local run with LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 did not hang (2404 passed, 45 s). The cause is not known.

Hazards found (each waits on a pool thread for the kernel or a child process):
- StdioServerProcessTests.swift:216: waitid with no WNOHANG.
- StdioServerProcessTests.swift:433: signal(SIGPIPE, SIG_DFL) for the whole process while other tests run.
- FileWalker.swift:151-153: reads stdout before stderr, then waitUntilExit (a stderr larger than 64 KiB deadlocks).
- TestSupport.swift:201: waitUntilExit with pipes that nothing reads.
- ShellRunnerTests.swift:231, OutputBufferTests.swift:160: waitUntilExit and reads.

The owner decides the fix and the CI change (A, B, C in the report).

#bad-test