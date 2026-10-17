---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m545mbrfrmd069k73e0tr0tw
  text: |-
    ### owner decision (2026-10-17), from ^t9dc8nb
    - ManualRunClock.waitForSleepers(atLeast:) in FoundationModelsExtras has no cancellation handler. In this repo, use the test-side wrapper waitForSleepers(atLeast:orUntil:) (Tests/FoundationModelsMultitoolTests/Support/ManualRunClockWaits.swift) at each call site in this group, with the end of the call as the second event. Groups 4 and 5 together hold 11 such call sites. Do not change Extras.
  timestamp: 2026-10-17T05:33:52.271718+00:00
- actor: claude-code
  id: 01m54hzhen8y8j56872wtw0pgh
  text: |-
    ### two more items for this card (found on ^8y8htqx, 2026-10-17)
    - Tests/FoundationModelsMultitoolTests/MCPServerCallTests.swift:605 calls ManualRunClock.waitForSleepers(atLeast:) directly. It is an MCP test, not a shell test, and group 3 (^c1v08m3) is done. Move it to the wrapper waitForSleepers(atLeast:orUntil:) here, with the end of the call as the second event (owner decision B).
    - Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:298 has the same journal wait after close() as the waits of ShellSessionSweepTests that went on ^vg01093 in group 4. It is not on ^vg01093. Find a second event for it; if none exists without a production change, add its line to ^vg01093 with the reason.
    - Groups 4 and 5 hold 11 waitForSleepers call sites. Group 4 moved 4. The 6 that stay: RunCodeToolTimeoutTests (4), SuspendedContextTests (1), and MCPServerCallTests.swift:605 (above).
  timestamp: 2026-10-17T09:09:41.461440+00:00
- actor: claude-code
  id: 01m54m7ymqm9nnrtt5nm7m58f2
  text: |-
    Research and implementation (in the tree, not committed):
    - Scope: JSCInterpreterTests, RunCodeToolTimeoutTests, SuspendedContextTests, HardeningTests, MultiToolExecutionTests, SandboxGlobalsTests and its fixture, InlineSettleGraceTests, RegistrySwapTests, RunBindingTests, plus SearchToolsToolTests (it called the one helper that changed). MCPServerCallTests.swift:605 and MCPSessionSweepTests.swift:298 from the group 4 comment.
    - Discovery: the teardown of a JSC run cancels each pending host call (PromiseRegistry.cancelAllPending in LiveRun.tearDown). Thus a gate wait inside an async host function ends when the run ends. The waits in host functions are part of the run under test and are not counted.
    - Discovery: ToolContext.wait(completionToken:seconds: nil) adds no sleeper on the run clock (RunPlaneActor.addWaiter makes a deadline task only for a deadline), and a cancel ends it. Thus it is a safe second event "the run ended" also on a ManualRunClock.
    - Shared code, no new scaffold: HeldCall.releaseOnArrival() is now releaseOnArrival(during:) (EventRace.start with the end of the work as second event; the old form is removed, its 5 callers moved). New TerminalDetail.waitForEnd(of:in:) and TerminalDetail.runEnd(of:in:) give the run-end event. New GatedTool.requireStart(orUntil:sourceLocation:) (EventRace.requireOpen); GatedTool.waitUntilStarted() is removed (no caller is left). ProgressSignalSink.gate(for:) is no longer private, and waitForProgress is removed. In SandboxGlobalsFixtures the progressPosted gate is a TestGate now (a cancel ends its wait); the run gate stays a SettlementGate, thus the run body does not change. New accessor ElicitationPrimitiveSchema.stringSchema for the require macro.
    - MCPServerCallTests.swift:605 was already moved to waitForSleepers(atLeast:orUntil:) with the end of the call (before this card). No change.
    - MCPSessionSweepTests.swift:298: no second event without a production change (the settlement of the run comes before the journal write, thus a race with it can fail a correct product). Line added to ^vg01093.
    - guard-and-return in test bodies replaced with the require macro: JSCInterpreterTests 2, InlineSettleGraceTests 1 (now TerminalDetail.settledEvent), SandboxGlobalsTests 1.
    - Out of scope, new card ^8e829q0: SandboxPreflightTests.swift:146 (the internal hook waitForWaitingCallers has no cancel handler) and WebFetcherTests.swift:244 and :250.
    - Mutation check: HardeningTests.reportingInfiniteLoop was "while (false) {}" one time (no start report). swift test --filter on cancellationTerminatesInfiniteLoopSnippet: exit 1, "failed after 0.010 seconds with 1 issue" (Expectation failed: hasArrived(), the run ended before the snippet reported its start). Before the change, started.hold.arrival.wait() had no end. The mutation is reverted.
    - swift build --build-tests: exit 0, no warning from the test files. swift test, one full run: exit code 0, "Test run with 2450 tests in 212 suites passed after 5.325 seconds". The only warning is the build-system line "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
  timestamp: 2026-10-17T09:49:14.263036+00:00
- actor: claude-code
  id: 01m54m8e5310vjbas0d94k1se9
  text: |-
    ### implement — changed
    - evidence: 14 test files changed, no new file, no production change: Support/TestGate.swift, Fixtures/TerminalDetailFixtures.swift, Fixtures/SuspendedContextFixtures.swift, Fixtures/SandboxGlobalsFixtures.swift, JSCInterpreterTests.swift, RunCodeToolTimeoutTests.swift, SuspendedContextTests.swift, HardeningTests.swift, MultiToolExecutionTests.swift, RunBindingTests.swift, SearchToolsToolTests.swift, RegistrySwapTests.swift, InlineSettleGraceTests.swift, SandboxGlobalsTests.swift.
    - counts: 26 cases fixed (JSC 5 with the run helper of 21 tests, runCode timeout 8, suspended context 3, hardening 3, execution 2, run binding 1, search tools 1, registry swap 1, inline settle 1, sandbox globals fixture 1); 5 cases already fixed (MCPServerCallTests.swift:605, the floating host call wait of JSC that the run teardown ends, 2 deliveredRunMail waits, callPastSettlePeriod in startScriptedRun); waitForSleepers call sites moved to the wrapper: 5 (RunCodeToolTimeoutTests 4, SuspendedContextTests 1; the 6th, MCPServerCallTests.swift:605, was already moved); 8 lines added to ^vg01093; 4 guard-and-return replaced with the require macro; new card ^8e829q0.
    - mutation check: HardeningTests cancellationTerminatesInfiniteLoopSnippet with no start report failed after 0.010 s (no hang), reverted.
    - test: swift test, one full run, exit code 0, 2450 tests in 212 suites passed.
    - next: test, then review. The task stays in doing.
  timestamp: 2026-10-17T09:49:30.147416+00:00
- actor: claude-code
  id: 01m54mb12y6y938dwqcevxne3w
  text: |-
    ### test - green
    - evidence: `swift test` one run, exit code 0. Swift Testing summary: "Test run with 2450 tests in 212 suites passed after 4.446 seconds." No failure, no skipped test, no compiler warning in the code.
    - note: The build tool printed one line, "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle. It comes from the build system and not from project code.
    - next: review.
  timestamp: 2026-10-17T09:50:55.070639+00:00
- actor: claude-code
  id: 01m54mbvpdes2b3640vsbz9fdm
  text: |-
    ### commit — changed
    - evidence: one local commit "test: end JSC and runCode test waits on a second event". Tests only. Kanban files are in the same commit. Not pushed.
    - next: review
  timestamp: 2026-10-17T09:51:22.317454+00:00
depends_on:
- 01M53W31F0R9FSZW7FV8Y8HTQX
position_column: doing
position_ordinal: '8180'
title: 'T1 group 5: JSC and runCode test waits with no second event'
---
Split from ^nvxckvr (test rule T1). The list (the JavaScriptCore sandbox and runCode waits in the unit tests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits.

Do: make each wait end on the first of two events: the expected event, or an existing end event (the run ends, the snippet promise settles, the call ends). A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Show for at least one case that the test now fails (not hangs) when the expected event does not come (a one-time mutation that you revert). No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes #t1