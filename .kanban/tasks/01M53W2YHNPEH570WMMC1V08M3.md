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
- actor: claude-code
  id: 01m54dq8v9gg18tn4yfrp78hnr
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 17b9f1c). 10 findings: 10 confirmed, 9 refuted, 21 attempted. 17 files reviewed. 8 .kanban files not reviewed (ignore rule). Findings: LiveCatalogTests.swift:465, MCPElicitationTests.swift:977, MCPServerCallTests.swift:429, MCPServerCallTests.swift:535, MCPSessionSweepTests.swift:332, MCPTracePropagationTests.swift:283, MCPTracePropagationTests.swift:310, RegistryRebuildTests.swift:254, ResilienceTests.swift:728, ResilienceTests.swift:842. All 10 are in files that this commit changes. No finding is about the accepted decisions (^vg01093 exception list, the bare-call cancel notice drain on ^bxxjdz6).
    - next: implement the 10 items in the "Review Findings (2026-10-17 02:45)" section. The task stays in review.
  timestamp: 2026-10-17T07:55:16.201257+00:00
- actor: claude-code
  id: 01m54dr5erfkt8w14j0hjep84p
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 17 files (64 MCP waits; EventRace; MCPRelistWait; 16 lines on ^vg01093)
    - test: green — swift test, exit 0, 2449 passed, 0 failed, 0 skipped
    - commit: 17b9f1c (the commit comment names d85969d, the sha before the amend)
    - review: findings — LiveCatalogTests.swift:465; MCPElicitationTests.swift:977; MCPServerCallTests.swift:429, :535; MCPSessionSweepTests.swift:332; MCPTracePropagationTests.swift:283, :310; RegistryRebuildTests.swift:254; ResilienceTests.swift:728, :842
    - note: the tag "require" came from the findings text (a macro name with a hash). I keep it, because an untag also removes the word from the findings, and the findings must stay word for word.
  timestamp: 2026-10-17T07:55:45.496490+00:00
- actor: claude-code
  id: 01m54e8pnmmwcgfcg7jdy6tae5
  text: |-
    Picked up the 10 findings of "Review Findings (2026-10-17 02:45)". Plan and discoveries:
    - The cross-file step is start-work, wait for the first of (event, end of work), then the require macro on the event. It is in about 20 sites in 10 files. Shared helpers go in Support/EventRace.swift: EventRace.watch(_:awaiting:requiring:orFail:), watch(_:untilOpen:orFail:), watch(_:untilArrivalAt:orFail:) and requireOpen(_:orFirstOf:orFail:). Each passes the source location of the caller to the require macro, thus a failure names the line of the test.
    - The read-the-generation, act, wait-for-the-re-list step goes in Support/MCPRelistWait.swift: waitForNotifications(of:count:sentBy:) and waitForRelist(of:after:sentBy:). LiveCatalogTests, SurfaceRefresherTests and RegistryRebuildTests use them. waitForRelist(of:reaching:) has no caller after this, thus it is removed.
    - RegistryRebuildTests: CatalogMark and mark() are removed. waitUntilCatalog now takes the change as a closure, and it reads the epoch before the change. advanceToGreeterAdded(scripted:server:) and addAndAnnounce(_:on:) hold the repeated blocks.
    - File-private helpers that the findings name: MCPServerCallTests.watchHeldCall(on:_:) and expectOneCancelledNotification(recordedBy:afterDisconnectOf:); MCPSessionSweepTests.startTheCall(on:_:) on the wait path of waitForTheCall; MCPTracePropagationTests.startHangingCall(on:gate:); ResilienceTests.startDisconnectAwaitingClose(of:gate:); MCPElicitationTests.startURLAnswer(on:generation:untilOpen:orFail:).
    - Not changed (a different shape): requires that read an async value (startEliciting, startHeldHostFlow, startContextURLFlow, startContextURLQuestion), whileHolding (require inside do/catch with a release), ResilienceTests.startTeardown (returns a flag), and the bare-call wait in MCPServerCallTests that has no disconnect (exception list).
  timestamp: 2026-10-17T08:04:47.412406+00:00
- actor: claude-code
  id: 01m54efh14jcs510ba0b4qrjn6
  text: |-
    ### implement — changed
    - evidence: 14 test files changed (no production code). Shared helpers in Support/EventRace.swift: EventRace.watch(_:awaiting:requiring:orFail:), watch(_:untilOpen:orFail:), watch(_:untilArrivalAt:orFail:), requireOpen(_:orFirstOf:orFail:). Shared helpers in Support/MCPRelistWait.swift: waitForNotifications(of:count:sentBy:), waitForRelist(of:after:sentBy:); waitForRelist(of:reaching:) removed (no caller). File helpers: MCPServerCallTests.watchHeldCall(on:_:), expectOneCancelledNotification(recordedBy:afterDisconnectOf:); MCPSessionSweepTests.startTheCall(on:_:); MCPTracePropagationTests.startHangingCall(on:gate:); MCPElicitationTests.startURLAnswer(on:generation:untilOpen:orFail:); ResilienceTests.startDisconnectAwaitingClose(of:gate:); RegistryRebuildTests.advanceToGreeterAdded(scripted:server:), addAndAnnounce(_:on:), waitUntilCatalog(of:notifications:changedBy:...). Same step also moved to the shared helpers in LostCallTests, RegisteredJournalOpTests, ScriptedServerSelfTests, MCPLogRecordTests, SurfaceRefresherTests. Findings checked 10/10.
    - test: swift build --build-tests, no errors. swift test, one full run, exit code 0: "Test run with 2449 tests in 212 suites passed after 3.299 seconds." Only warning: "missing creator for mutated node" for the mlx-swift_Cmlx.bundle path (a dependency).
    - note: ^vg01093 has a comment about the moved call site of waitUntilToolListChangedGeneration.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T08:08:31.012846+00:00
- actor: claude-code
  id: 01m54ej3yhxkbw0h4nakpgjnhh
  text: |-
    ### test - green
    - command: swift test (one run, output saved to a file)
    - exit code of swift test: 0
    - Swift Testing summary: Test run with 2449 tests in 212 suites passed after 3.866 seconds.
    - failures: 0. recorded issues: 0. skipped tests: 0.
    - one build-system warning is in the output: "missing creator for mutated node" for the mlx-swift_Cmlx.bundle of a dependency. It is not from package code. I did not change it.
    - next: review.
  timestamp: 2026-10-17T08:09:55.921981+00:00
- actor: claude-code
  id: 01m54ejy922s662p2e5pq57jzf
  text: |-
    ### commit — changed
    - evidence: one local commit, subject "test: share the event-wait helpers and fix 10 review findings". Not pushed. The commit has the test changes and the .kanban files. The sha is in git log.
    - tests before commit: swift test, exit 0, 2449 passed, 0 failed, 0 skipped.
    - next: review.
  timestamp: 2026-10-17T08:10:22.882215+00:00
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

## Review Findings (2026-10-17 02:45)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 8 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/LiveCatalogTests.swift:465` `reuse/reuse` — The read of toolListChangedGeneration, followed by waitForRelist(of:reaching:), is repeated inline. The same pair appears earlier in the same test file. The MCPTestSupport helper exists but each caller rebuilds the generation arithmetic by hand. Give MCPTestSupport a helper that reads the generation, runs the action, and waits for the re-list to reach the count. Or pass the count into one helper that takes the action as a closure. Use it at both sites.
- [x] `Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift:977` `reuse/reuse` — The race of a URL answer against the handler arrival, followed by a check that the arrival is open, is written out again in the same file. The second copy at line 1130 has the same shape. One helper should hold this shape. Add one helper that takes the answer work and an arrival gate, starts the race, and requires the gate to be open. Call it from both tests. Keep the release and the cancel steps in each test.
- [x] `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift:429` `duplication/duplication` — The `#require` that the held call reached the server is repeated in the same file. A later edit to the message or the check can miss one copy. Add one helper in this file that waits for the arrival and requires it, and call it from `cancellationSendsTheNotificationAndThrows` and `aBareCallTimesOutOnlyOnTheInjectedClock`.
- [x] `Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift:535` `duplication/duplication` — The read of the recorded cancellation notification and its check are repeated in two tests of the same class. Extract a helper such as `expectOneCancelledNotification(scripted:server:)` and call it from both tests.
- [x] `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:332` `duplication/duplication` — The native-shape test repeats the arrival wait of `waitForTheCall` inline. The race and the on-the-wire check are split across two places, so a change to the wait rule must be made in both. Extract the race step into a helper that accepts the started call, or make `waitForTheCall` take the call task so this test and the parked test share one wait path.
- [x] `Tests/FoundationModelsMultitoolTests/MCPTracePropagationTests.swift:283` `reuse/reuse` — The EventRace.start call, its awaiting closure, and the following #require are copied verbatim into reconnectRecordsASpanEvent (lines 309-313). The same wait-for-handler setup now exists twice in one file, so a fix to one copy will not reach the other. Move the start-and-wait pair into one private static helper in MCPTracePropagationTests (for example, startHangingCall(on:gate:)) that returns the call task, and call it from both tests. Keep the helper beside the existing hangingTool(opening:) factory.
- [x] `Tests/FoundationModelsMultitoolTests/MCPTracePropagationTests.swift:310` `duplication/duplication` — The `EventRace.start` call and the following `#require` in `reconnectRecordsASpanEvent` are the same as in `transportDropRecordsASpanEvent`. A fix to one copy can drift from the other. Move the start-and-require step into one private helper in this file, for example `startCallAwaitingHandler(server:gate:)`, and call it from both tests.
- [x] `Tests/FoundationModelsMultitoolTests/RegistryRebuildTests.swift:254` `duplication/duplication` — The three-line block that takes the catalog mark, advances the scenario, and waits for the greeter to appear is repeated in `rebuildAfterARemoveDropsTheVerb`. The same block is in `rebuildAfterAnAddGivesTheNewVerbAndKeepsTheFirstRegistry`. Extract a helper such as `advanceToGreeterAdded(scripted:server:)` that returns nothing, and call it from both tests.
- [x] `Tests/FoundationModelsMultitoolTests/ResilienceTests.swift:728` `duplication/duplication` — `disconnectWaitsForTheFactoryOfAPendingAttempt` repeats the start-and-require step that `connectUntilOrphaned` already performs. The copy is near-verbatim, so a change to the wait rule must be made twice. Extract the start-and-require step, with the arrival gate and the failure message as parameters, and use it from both `connectUntilOrphaned` and this test.
- [x] `Tests/FoundationModelsMultitoolTests/ResilienceTests.swift:842` `duplication/duplication` — `aLateDisconnectOfAnOldClientNeverClosesTheCurrentConnection` repeats the disconnect start-and-require block of `freshConnectIsNotBlockedByADisconnectWhoseTransportHangs`. Extract one helper, for example `startDisconnectAwaitingClose(of:gate:)`, and call it from both tests.