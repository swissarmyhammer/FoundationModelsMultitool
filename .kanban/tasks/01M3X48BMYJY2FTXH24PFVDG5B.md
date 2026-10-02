---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3yk67xc11scmgpdntv4sqc5
  text: |-
    Research (implement step):
    - Item 1 (MultiToolExecutionTests.sandboxWaitIsRemoved...): the inline settle grace is measured in FoundationModelsExtras (`RunPlane.wait` uses `Task.sleep`). That is a remote package, so no clock seam can go there from this repo. Plan: the prevailing pattern of `InlineSettleGraceTests.quickSnippetAnswersBesideABusySlowTool` (^3np5yzj). The gated snippet runs on the session mount with grace 0 (pending at once). The collector snippet runs on a second mount whose grace is only the hang bound `TestPoll.deadline`. It settles at once, because `wait()` throws.
    - Item 2 (CLIAnswerDrainTests): add a `clock` to `CLIMailWait` (default `ContinuousClock`). The tests use `GatedClock`. Note: the 50 ms quiet period was also a window. A quiet timer that ends between two events of the mail answer stops a correct drain early.
    - Item 3 (LoopbackHTTPServer.requestTimeout): URLSession has no clock seam. The stale doc says TestPoll waits 10 s. It is 300 s now. Plan: the caller gives the bound, and the bound is the shared hang guard (`TestHangGuard`). The loopback is then never the first bound that ends a correct run.
    - Items 4, 5, 6 (RegisteredJournalOpTests, ScriptedServerSelfTests, MCPServerCallTests, MCPSessionSweepTests): add a scripted MCP tool that holds each call on a `ReleaseGate` and records the arrival. A test waits for the arrival (event), acts, then releases the gate.
    - Item 7 (LiveCatalogTests): with `ManualClock` the coalesce window ends at once, so a slow burst can split into two re-lists. Plan: `GatedClock` holds the window until `toolListChangedGeneration` counted the whole burst, then opens it. Read `catalogEpoch` and `recordedSleeps` in place of the 200 ms sleep. The same cause is in `epochsStrictlyIncreaseAcrossEmissions` and in the second sleep of `reconnectThroughRetainedFactoryEmitsOneSnapshot`, so those get the same change.
  timestamp: 2026-10-02T15:19:41.228242+00:00
- actor: claude-code
  id: 01m3yktyxbb84hn7kt384c0xe7
  text: |-
    Implementation landed (not committed):
    - Production seam: `CLIMailWait.clock` (`any Clock<Duration>`, default `ContinuousClock`). `drainMailAnswers` sleeps both bounds on it. RED was the compile failure of the test that passes `clock:`.
    - New test helper `Tests/FoundationModelsMultitoolTests/Support/HeldScriptedTool.swift`: a scripted MCP tool that records each arrival and holds the call on a `ReleaseGate` until the test releases it. Used in ScriptedServerSelfTests, RegisteredJournalOpTests, MCPServerCallTests (cancel case and bare-call case) and MCPSessionSweepTests. The 1000-step and 30 s tools are gone.
    - CLIAnswerDrainTests: each drain runs on a `GatedClock`. The mail test opens the quiet period only after the mail answer line is printed. The time-limit test opens the clock and checks that the time limit is the one sleep. A new unit test checks `CLIMailDrain.isSettled` with an open run. It replaces the 200 ms late-mail delay as the proof that only the open run keeps the drain alive.
    - LiveCatalogTests: `emitBurstInOneWindow` holds the coalesce window on a `GatedClock` until `toolListChangedGeneration` counted the burst. The two 200 ms sleeps are replaced by reads of `catalogEpoch` and `recordedSleeps`.
    - MultiToolExecutionTests: the gated snippet uses grace 0. The collector runs on a second mount whose grace is the `TestPoll` hang bound (pattern of ^3np5yzj).
    - LoopbackHTTPServer: `start()` is now `start(hangBound:)`. Callers give `TestHangGuard.seconds` (new, 600 s). The stale doc (TestPoll 10 s) is gone. URLSession has no clock seam, so the timeout is now only the hang guard of the test process. A reviewer may read this as a raised timeout. The reason it is not: the request ends on the event of its response, and the bound no longer is shorter than the hang guards of the test.
    - Same cause, same files: RegisteredJournalOpTests `sleep 30` became `tail -f /dev/null` (ends only on the cancel). LiveCatalogTests `epochsStrictlyIncreaseAcrossEmissions` and `reconnectThroughRetainedFactoryEmitsOneSnapshot` got the same change as the coalesce test.
    - Not changed: FoundationModelsExtras `RunPlane.wait` still sleeps on the real clock (remote package). `ScriptedServerSelfTests.transportDropMidCall` (150 ms) and `timedMutationDelay` (20 ms) cannot fail on a slow machine, so they are out of scope.
    - Targeted run: 100 tests in 10 suites passed. Full `swift test`: 1893 tests in 155 suites passed. The one warning is the SwiftPM build note `missing creator for mutated node ... mlx-swift_Cmlx.bundle`, from the build system and not from code.
  timestamp: 2026-10-02T15:31:00.139833+00:00
- actor: claude-code
  id: 01m3ykv1t9vmkycyq045b2patv
  text: |-
    ### implement — changed
    - evidence: 15 files — Sources/MultitoolCLI/CLIAnswerDrain.swift; Tests/FoundationModelsMultitoolTests/{CLIAnswerDrainTests, LiveCatalogTests, LoopbackHTTPServerTests, MCPServerCallTests, MCPSessionSweepTests, MultiToolExecutionTests, RegisteredJournalOpTests, ScriptedServerSelfTests}.swift; Tests/FoundationModelsMultitoolTests/Support/{MCPTestSupport, HeldScriptedTool (new)}.swift; Tests/Support/MCPTestServer/LoopbackHTTPServer.swift; Tests/Support/MultitoolTestSupport/TestHangGuard.swift. `swift test`: 1893 tests in 155 suites passed.
    - next: /review
  timestamp: 2026-10-02T15:31:03.113985+00:00
- actor: claude-code
  id: 01m3ykzppjn9hsnx51e62zn424
  text: |-
    ### test - green
    - evidence: swift test (root) - 1893 tests in 155 suites passed, 0 failed, 0 skipped, 0 warnings from this package (one build-system warning about the mlx-swift_Cmlx bundle, not from our sources).
    - evidence: loaded run - swift build --build-tests --package-path IntegrationTests was running (confirmed with pgrep) while swift test --filter on the 8 changed suites ran: 84 tests in 8 suites passed.
    - evidence: swift build --build-tests --package-path IntegrationTests - Build complete, 0 errors.
    - next: review.
    task: ^pfvdg5b
  timestamp: 2026-10-02T15:33:35.570146+00:00
- actor: claude-code
  id: 01m3ym0mqq7km7ehbdn07w9a21
  text: |-
    ### commit — changed
    - evidence: this commit: test(root): wait for events or use an injected clock in place of real-time windows
    - next: review
  timestamp: 2026-10-02T15:34:06.327724+00:00
- actor: claude-code
  id: 01m3ymvtx4tk133va8q3326pjm
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 115a5c4): 0 findings, 0 confirmed, 0 refuted, 14 attempted, 0 failed. 13 files reviewed. 4 .kanban files were not reviewed (.reviewignore). `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, so no file-scoped review was necessary.
    - judgment 1: `LoopbackHTTPServer.start(hangBound:)` with `TestHangGuard.seconds` (600 s) is a hang guard, not a widened deadline. The old 30 s bound was a real-time window: the SSE stream stays open for the whole test body, and `TestPoll.deadline` is 300 s. The new bound is the same value as the `.timeLimit` of the test process. Each request ends on the event of its response, so a correct run never meets this bound.
    - judgment 2: the `runCode` settle grace on the real clock is not a speed check. The gated snippet holds on a `ReleaseGate` with grace 0, so it is pending at once. The collector throws at its first statement and settles, and the wait ends on that event. `TestPoll.deadline` is only its hang bound (pattern of ^3np5yzj).
    - next: none. The task is in done.
    task: ^pfvdg5b
  timestamp: 2026-10-02T15:48:57.380686+00:00
- actor: claude-code
  id: 01m3ymwb1ef27jgcr7r8k4kde5
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 15 files; each listed real-time window now waits for an event or uses an injected clock (new seam CLIMailWait.clock, new helper HeldScriptedTool)
    - test: green — swift test 1893 passed; the 8 changed suites passed 84 tests under load; IntegrationTests build passes
    - commit: 115a5c4
    - review: clean — 0 findings; the 600 s loopback bound is a hang guard, and the runCode grace test ends on an event; task moved to done
  timestamp: 2026-10-02T15:49:13.902734+00:00
position_column: done
position_ordinal: ffff9180
title: Remove the remaining short real-time windows from root tests
---
## What
The search of ^kdtrmhv found more tests that need a real-time window to hold. Each needs a production seam or a new event, so ^kdtrmhv did not change them. The user decision is: "no test checks the speed of the machine".

- `MultiToolExecutionTests.sandboxWaitIsRemovedAndTheRunComesBackAsOneMail`: `shortInlineSettleGrace` (1 s). The gated snippet must outlast it, and the second snippet must settle in it.
- `CLIAnswerDrainTests`: `unreachedTimeLimitSeconds` (30 s). `CLIMailWait` has no clock seam.
- `LoopbackHTTPServer.requestTimeout` (30 s). Its doc is stale.
- `RegisteredJournalOpTests`: a 600 ms in-flight window.
- `ScriptedServerSelfTests.cancelledNotificationRecording`: a 50 ms lead.
- The windows in `MCPServerCallTests` and `MCPSessionSweepTests`.
- `LiveCatalogTests.coalescesRapidBurstIntoOneRelist`.

A lower bound (`elapsed >= X`) cannot fail on a slow machine. It is not in this list.

## Do
- For each item: wait for an event, or inject a clock (add the seam where none exists).

## Acceptance Criteria
- [x] Each item above waits for an event or uses an injected clock.

## Tests
- [x] Root `swift test` passes once.