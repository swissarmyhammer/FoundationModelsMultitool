---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m54bbn5c8c5pfbhghkzq4bs3
  text: |-
    Picked up. Research so far:
    - The list in ^nvxckvr gives counts by file, not lines. I check each wait in the MCP test files (not MCPElicitationTests) against the current code.
    - start(_:awaiting:cleaningUpOnThrow:), endWait, whileHolding and releaseHeldCall are private to MCPElicitationTests. The other MCP suites need the same scaffold. Plan: move start and endWait to one shared file (Support/EventRace.swift) with one more primitive firstOf(_:or:) (the first of two cancel-aware waits). ResilienceTests.startTeardown is one more copy of that scaffold.
    - Second event for a wait for a recorded notification: the end of the message loop of the wrapped MCP.Server (ScriptedServer). The swift-sdk Server runs each notification handler inline in its receive loop, thus each notification is recorded before the loop ends. An in-memory client disconnect finishes the receive stream of the server end. MCPServer.disconnect() first drains each notifications/cancelled, thus the notice is on the wire before the transport closes. Plan: ScriptedServer ends its count waits when the loop ends; the test disconnects and then waits.
    - catalogUpdates of MCPServer finishes only at deinit. A snapshot wait thus has no stream end during a test. The re-list end (coalescingTask) is an existing event, but the wait for its start is the hook waitUntilToolListChangedGeneration, which is on ^vg01093 already.
    - SurfaceRefresher writes no event for a snapshot that does not move the catalog (apply returns at once). A stage wait thus has no second event for that path.
    - MCPServer.waitUntilReady() has no cancel handler. It cannot be one side of a race without a production change.
  timestamp: 2026-10-17T07:13:58.444380+00:00
- actor: claude-code
  id: 01m54d1s9bm0p39n3q559strx4
  text: |-
    Implementation (in the tree, not committed):
    - New Support/EventRace.swift: firstOf(_:or:), watch(_:), start(_:awaiting:cleaningUpOnThrow:), endWait(_:). MCPElicitationTests and ResilienceTests.startTeardown now use it; their private copies are removed.
    - ScriptedServer: when its message loop ends (the transport closed), waitForRecordedNotifications and waitForElicitationResults end. scheduleMutation returns its task.
    - Support/MCPConnectionScope.swift: notifications(recordedBy:afterDisconnectOf:count:) (disconnect, then wait; the loop end is the second event) and waitFor(_:orPingOf:) (a ping is the barrier for a notification to a client).
    - New Support/MCPRelistWait.swift: waitForRelist(of:reaching:) and waitForRelistEnd(of:). SurfaceRefresherTests uses it in place of its private copy.
    - Each wait for an arrival, a discard or a handler now races the end of its call or connect, and then a require fails at once when the event did not come: MCPServerCallTests, MCPSessionSweepTests, ScriptedServerSelfTests, ResilienceTests, MCPLogRecordTests, LostCallTests, MCPTracePropagationTests, RegisteredJournalOpTests.
    - LiveCatalogTests: each snapshot wait first requires that catalogEpoch reached the count, and each re-list wait ends on the end of the re-list. RegistryRebuildTests: each catalog wait waits for the re-list end, and then requires the epoch and the condition before it reads the stream.
    - StdioServerProcessTests: a require on kill(pid, SIGKILL) == 0 before each waitUntilZombie.
    Counts (my count against the file counts of ^nvxckvr): 64 cases fixed; 4 cases were already fixed or already end (SurfaceRefresherTests.waitUntil and LiveCatalogTests.waitForSnapshots by group 1, ServerModeTests by group 1, ResilienceTests:694 ends when the double closes); 28 cases in 16 lines added to ^vg01093.
    Mutation check: in ScriptedServerSelfTests.cancelledNotificationRecording, the client did not send the cancel (one time). The test failed after 0.003 s with 3 issues (recorded.count is 0); it did not hang. The mutation is reverted.
    Test: swift test, one full run, exit code 0: "Test run with 2449 tests in 212 suites passed after 3.452 seconds."
    Possible product gap: MCPServer.disconnect() does not drain the notifications/cancelled of a bare-call timeout (CancellationNotices does not track it). No product change in this card.
  timestamp: 2026-10-17T07:43:32.139798+00:00
- actor: claude-code
  id: 01m54d1zz3m3304rkeva0dm2k5
  text: |-
    ### implement — changed
    - evidence: 17 test files: 15 changed, 2 new (Support/EventRace.swift, Support/MCPRelistWait.swift). 64 cases fixed, 4 already fixed or already end, 16 lines (28 cases) on ^vg01093. Mutation check: cancelledNotificationRecording with no cancel failed after 0.003 s, no hang, reverted. swift test, one run, exit code 0, 2449 tests in 212 suites passed.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-17T07:43:38.979317+00:00
- actor: claude-code
  id: 01m54d4nhvzbqtcvqfwtk8taak
  text: |-
    ### test — green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing line: "Test run with 2449 tests in 212 suites passed after 3.720 seconds." Zero failures. Zero skipped tests.
    - warnings: one build-system warning only, "missing creator for mutated node" for the mlx-swift_Cmlx.bundle path. It comes from a dependency, not from this package.
    - code change: none in this step.
    - next: review.
  timestamp: 2026-10-17T07:45:06.619827+00:00
- actor: claude-code
  id: 01m54d5ef1t7jwy9jchwh02ke1
  text: |-
    ### commit — changed
    - evidence: d85969d test: end each MCP test wait also on the failure event
    - next: review
  timestamp: 2026-10-17T07:45:32.129417+00:00
depends_on:
- 01M53W2TYXASHFQ2PZV6MHKP5E
position_column: doing
position_ordinal: '8180'
title: 'T1 group 3: MCP test waits with no second event'
---
Split from ^nvxckvr (test rule T1). The list (the waits in the MCP test files other than MCPElicitationTests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits.

Do: make each wait end on the first of two events: the expected event, or an existing end event (the call ends, the transport closes, the stream finishes). A wait for a notification can nearly always also end on the close of its transport or the end of its call. Use the shared FirstEvent helper (from ^nvxckvr) where it fits. A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Show for at least one case that the test now fails (not hangs) when the expected event does not come (a one-time mutation that you revert). No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes #t1