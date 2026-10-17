---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m55bhew50vexbvsw3mfebew8
  text: |-
    Research (implement, 2026-10-17):
    - MCPServer.waitUntilReady() is public API. FoundationModelsACPAgent calls it: Sources/FoundationModelsACPAgent/Tools/MCPComposition.swift (one site) and Tests/FoundationModelsACPAgentTests/MCPCompositionTests.swift (two sites). Each call already uses try. FoundationModelsAgents and the other sibling repos do not call it. The signature does not change; the new behavior is a CancellationError for a cancelled caller.
    - waitUntilTransportDropped and waitUntilToolListChangedGeneration(reaches:) are internal test hooks. No sibling repo calls them. Callers: LostCallTests (one site) and MCPRelistWait.waitForNotifications(of:count:sentBy:).
    - The initial state of MCPServer is .connecting. Thus waitUntilReady() on a server that never connects has no end except a cancel.
    - MCPServer.disconnect() moves the generation before it closes the transport, thus a disconnect never reports a transport drop. A new connect does the same (retireCurrentClient()).
    - Plan: waitUntilReady() checks the cancel at the top of each loop step and waits through TestHookWait.suspend (the cancel handler). The two hooks become async throws. They throw ConnectionHookWaitError.connectionEnded when the connection ends first: a thrown error ends the test at once with a reason, and the callers need only one try. A wait that starts when the end already came (state .disconnected, or a drop for the generation hook) throws at once.
    - Item 4: SurfaceRefresher.Rebuilding.apply(_:) is private. Only the follow loop of the watch task that start() makes calls it, and it returns Void. A test cannot await it.
    - Item 5: ScriptedServer.waitForRecordedNotifications(count:) also ends when the message loop of the scripted server ends. An in-memory client disconnect ends that loop (InMemoryTransport.handlePeerDisconnection).
  timestamp: 2026-10-17T16:36:23.045265+00:00
- actor: claude-code
  id: 01m55c24j4qy6f346n234ndctx
  text: |-
    ### implement — changed
    - evidence: 13 files. Sources: MCP/MCPServer.swift, MCP/MCPServer+Call.swift, MCP/MCPServer+LiveCatalog.swift, MCP/MCPServer+Connection.swift, MCP/MCPServer+ClientLifecycle.swift, TestHookWait.swift, new MCP/ConnectionHookWait.swift. Tests: new ConnectionHookWaitTests.swift, ResilienceTests.swift, LostCallTests.swift, LiveCatalogTests.swift, MCPSessionSweepTests.swift, Support/MCPRelistWait.swift.
    - 1: waitUntilReady() checks the cancel at each step and suspends through TestHookWait.suspend (no new copy of the scaffold). A cancel ends it with CancellationError. RED then GREEN: ResilienceTests aCancelEndsWaitUntilReadyWithCancellationError.
    - 2 and 3: the two hooks are now async throws and throw ConnectionHookWaitError.connectionEnded (a thrown error: the test fails at once with a reason, one try for each caller). Transport drop wait: ends on disconnect() and on a new connect (retireCurrentClient). Generation wait: ends on a transport drop and on disconnect(). Each also throws at once when the end came before the call. A new internal test hook waitUntilConnectionHookWaitIsRecorded() fixes the order of the tests (raced with the end of the wait, as the elicitation precedent). RED then GREEN: the 4 tests of ConnectionHookWaitTests.
    - Callers updated: LostCallTests (try), MCPRelistWait.waitForNotifications and waitForRelist (rethrows to throws), LiveCatalogTests dynamic toolset (try).
    - Public API: waitUntilReady() is public. FoundationModelsACPAgent calls it (Sources/FoundationModelsACPAgent/Tools/MCPComposition.swift, one site; Tests/FoundationModelsACPAgentTests/MCPCompositionTests.swift, two sites). Signature unchanged; new behavior: a cancelled caller gets CancellationError, also on a ready server. FoundationModelsAgents and the other siblings do not call it. The two hooks are internal and no sibling calls them. Sibling repos not changed. Before the push, the owner must see this change and these callers.
    - Item 4: not possible. SurfaceRefresher.Rebuilding.apply(_:) is private, returns Void, and only the follow(_:) loop of the watch task calls it. The 14 sites stay on ^vg01093.
    - Item 5: MCPConnectionScope.swift:92 already has a second event (the end of the message loop of the scripted server after the disconnect). MCPSessionSweepTests.swift:252 now goes through that helper with the server of the ground.
    - ^vg01093: one comment. Removed lines 3, 4, 6. Added ConnectionHookWaitTests.swift:124 (the drop is the event under test). Lines 7, 8, 9, 10 stay with the exact reason. 34 lines to 32, 49 sites to 47.
    - Not covered by a test: the cancel of a waitUntilReady() wait that is already suspended (the handler path). A test of only that path hangs on code without the handler; the new test ends on the old code because the release of the connect also ends it.
    - tests: swift test, exit 0, "Test run with 2458 tests in 214 suites passed". One build line "warning: missing creator for mutated node" for the mlx-swift_Cmlx bundle (a build-system line, also in the RED run before any change of this card). IntegrationTests not changed, thus no build there.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T16:45:29.540902+00:00
- actor: claude-code
  id: 01m55c4ycnfqykqzsndh3by9wy
  text: |-
    ### test - green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing line: "Test run with 2458 tests in 214 suites passed after 5.256 seconds."
    - no test failed. No test was skipped.
    - The build printed one SwiftPM build-system line: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle path. It comes from the package build graph. It is not from a source file in this repository.
    - next: review.
  timestamp: 2026-10-17T16:47:01.525921+00:00
- actor: claude-code
  id: 01m55c54gekxvqp35btj15de52
  text: |-
    ### decisions — owner (2026-10-17)
    - A. Public API change accepted: MCPServer.waitUntilReady() now ends with CancellationError on a cancel. The ACPAgent call (MCPComposition.swift:723) is in a throwing connect function, so the error goes up like the other connect errors. After the push, the owner re-runs the last ACPAgent CI run (it resolves Multitool from main) to check MCPCompositionTests.
    - B. Approved exception to the rule "no new production hook only for tests": Sources/FoundationModelsMultitool/Capabilities/MCP/ConnectionHookWait.swift:49 waitUntilConnectionHookWaitIsRecorded(). Reason: the new code is the wiring that resumes a wait in progress on a disconnect, a new connect or a drop; only a during-wait test proves it. The hook is internal, no product code waits on it, and it has the same form as waitUntilHostElicitationHeldWaitIsRecorded. The during-wait tests must fail on the old code (the implement step reported RED for the 4 tests in ConnectionHookWaitTests.swift).
  timestamp: 2026-10-17T16:47:07.790346+00:00
- actor: claude-code
  id: 01m55c5t4yv0ceg81wn7rz2n2g
  text: |-
    ### commit — changed
    - evidence: 6348e63 fix(mcp): end test-hook and ready waits on a cancel or a connection end
    - next: review
  timestamp: 2026-10-17T16:47:29.950165+00:00
- actor: claude-code
  id: 01m55cf2mzxrp0r7vwbj3dka0a
  text: |-
    ### review — findings
    - scope: review sha HEAD~1..HEAD (commit 0336b6b). The review engine examined 13 files. An ignore rule excluded 4 .kanban files.
    - counts: 2 findings, 2 confirmed, 1 refuted.
    - evidence: Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+LiveCatalog.swift:98 (duplication/duplication), Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift:600 (duplication/duplication).
    - note: The two findings are about duplicated code. The owner decisions do not include them. The approved exception for waitUntilConnectionHookWaitIsRecorded() applies only to the rule "no new production hook only for tests". It does not apply to the duplication rule.
    - next: Do the two items in the dated Review Findings section. The task stays in review.
  timestamp: 2026-10-17T16:52:33.567138+00:00
- actor: claude-code
  id: 01m55cg0bkpz6gc01rvg504v48
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files (waitUntilReady ends on a cancel; the two hooks throw ConnectionHookWaitError.connectionEnded; ConnectionHookWait wiring and an approved test hook; 5 new tests RED then GREEN; ^vg01093 34 to 32 lines)
    - test: green — swift test, exit 0, 2458 passed, 0 failed, 0 skipped
    - commit: 0336b6b (the commit comment names 6348e63, the sha before the amend)
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+LiveCatalog.swift:98; MCPServer.swift:600
  timestamp: 2026-10-17T16:53:03.987141+00:00
- actor: claude-code
  id: 01m55cqdgktrazqp5a0attbmj2
  text: |-
    Research (implement, review findings 2026-10-17 11:47):
    - A probe with swiftc -swift-version 6 gave "cannot form key path to actor-isolated property" for a key path to an actor property, also from inside the actor. Thus the key-path form of the findings does not compile.
    - Plan: one value type store TestHookWaiters<Value, Detail> (the waits by id, the next wait id, and the detail of each wait). It replaces ElicitationWaiters and the raw [Int: CheckedContinuation] stores and their separate id counters. One new overload TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:) does the id, the record and the end by id. The store goes in as a closure that gives inout access on the isolated actor.
    - One MCPServer helper suspendConnectionHookWait(...) holds the early return, the connection-ended throw, the suspend with .cancelled, the record step and throwIfConnectionEnded for the two connection hooks.
    - The same wiring is also in waitUntilTransportCloseIsAwaited(), waitUntilHostElicitationHeld(elicitationId:) and waitUntilHostElicitationHeldWaitIsRecorded(elicitationId:). They move to the same helper. ShellState has two more copies; it is not part of MCPServer, thus it stays as it is.
  timestamp: 2026-10-17T16:57:06.835834+00:00
- actor: claude-code
  id: 01m55d1fv3r0a235prgr9svmm8
  text: |-
    ### implement — changed
    - evidence: 9 source files, no test file changed. New store TestHookWaiters<Value, Detail> (Capabilities/TestHookWaiters.swift; git rename of MCP/ElicitationWaiters.swift, which it replaces). New overload TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:) and typealias TestHookWaiterStore in TestHookWait.swift. New helper MCPServer.suspendConnectionHookWait(unless:throwingIf:in:detail:) in MCP/ConnectionHookWait.swift. Changed: MCP/MCPServer.swift, MCP/MCPServer+Call.swift, MCP/MCPServer+LiveCatalog.swift, MCP/MCPServer+ClientLifecycle.swift, MCP/MCPServer+Elicitation.swift.
    - Finding 1: waitUntilTransportDropped() and waitUntilToolListChangedGeneration(reaches:) each are now one call to suspendConnectionHookWait. The second copy is deleted.
    - Finding 2: suspendUntilStateChange() and waitUntilConnectionHookWaitIsRecorded() each are now one call to the new TestHookWait.suspend overload. The duplicated body is deleted.
    - Key paths: Swift 6 gives "cannot form key path to actor-isolated property" (a swiftc -swift-version 6 probe, also from inside the actor). Thus the store goes in as a closure that gives in-out access: { server, access in access(&server.store) }. The id counter is in the value type store, as ElicitationWaiters had it.
    - Same cause removed in all of MCPServer: waitUntilTransportCloseIsAwaited(), waitUntilHostElicitationHeld(elicitationId:) and waitUntilHostElicitationHeldWaitIsRecorded(elicitationId:) also use the new overload. Deleted: nextTestHookWaiterID, nextReadinessWaiterID, nextTransportCloseAwaitedWaiterID, endTransportCloseAwaitedWait(_:), the private endToolListChangedGenerationWaits(with:where:), the hand-written resume loop in waitUntilTransportClosed(_:), and Dictionary.resumeAll(returning:) (no caller remained).
    - Findings checked: 2/2.
    - tests: swift test, one run, exit code 0. "Test run with 2458 tests in 214 suites passed after 4.608 seconds." XCTest: "Executed 0 tests, with 0 failures". The build printed the same SwiftPM line as before: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle path. The log also has one "SWIFT TASK CONTINUATION MISUSE" line for the test helper respawningThatHangsAfterFirstConnect(counter:hangArrival:) in ResilienceTests.swift. This change did not touch that helper.
    - New work: ShellState has two more waits with the same wiring. It is not part of MCPServer, thus it is recorded on the new task ^tg9909a.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T17:02:36.899954+00:00
- actor: claude-code
  id: 01m55d3zj24gge9y6263592gnf
  text: |-
    ### test - green
    - command: swift test (one run, exit code kept with echo of $?)
    - exit code: 0
    - summary line: Test run with 2458 tests in 214 suites passed after 6.810 seconds.
    - failures: 0. Skipped tests: 0. Code warnings: 0. The build log has one build-system note, "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is not a code warning.
    - SWIFT TASK CONTINUATION MISUSE lines: 3
      - hangForever() leaked its continuation without resuming it. (two lines)
      - respawningThatHangsAfterFirstConnect(counter:hangArrival:) leaked its continuation without resuming it. (known, a separate card holds it)
    - I did not fix the misuse lines. I only report them.
    - next: review
  timestamp: 2026-10-17T17:03:58.530799+00:00
- actor: claude-code
  id: 01m55d59sx30e7f9bwwvwenmb1
  text: |-
    ### commit — changed
    - evidence: 0039c0c refactor(mcp): share one test-hook wait store and one suspend helper
    - next: review
  timestamp: 2026-10-17T17:04:41.789492+00:00
position_column: doing
position_ordinal: '80'
title: End three MCPServer test-hook and ready waits on a cancel or a connection end, and check the last T1 waits
---
From the final exception list ^vg01093 (product gaps 1-3, owner decisions 2026-10-17).

1. MCPServer.waitUntilReady(): add a cancel handler. A cancel ends the wait with CancellationError. A wait that a cancel does not end is a defect also for production callers. Then the wait at Tests/FoundationModelsMultitoolTests/ResilienceTests.swift about line 1037 ends on a cancel.
2. MCPServer.waitUntilTransportDropped: a disconnect or a new connect ends the wait. Choose the result (a return value or a thrown error) from what the callers need, and keep it the same for 2 and 3.
3. MCPServer.waitUntilToolListChangedGeneration: a transport drop or a disconnect ends the wait, in the same way as 2.
For 1-3: a deterministic test for each new end that fails on the old code (RED), then the fix (GREEN). Then remove the lines that they fix from ^vg01093, with a comment that names each line and why.
Before the push: if one of them is public API, or a dependent package (ACPAgent at ../FoundationModelsACPAgent, Agents) calls it, send the change and the callers to the owner.

4. SurfaceRefresher.apply(): no new event for a no-op snapshot (a production hook only for tests). The 14 SurfaceRefresherTests sites stay on ^vg01093 with the reason. Check: if the caller awaits apply(), use its return as the end of the wait instead, and report if that works.

5. Check the two waitForRecordedNotifications sites that no group named: Tests/FoundationModelsMultitoolTests/Support/MCPConnectionScope.swift:92 and Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:252. Fix each one with a second event, or put it on ^vg01093 with the reason.

Rule T1. No .timeLimit, sleep, poll or retry. Do not delete a test. One full run of swift test. #elicitation-fixes #t1

## Review Findings (2026-10-17 11:47)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+LiveCatalog.swift:98` `duplication/duplication` — waitUntilToolListChangedGeneration(reaches:) repeats the step sequence of waitUntilTransportDropped(). Both return early when the event is already true, throw when the connection has ended, allocate a waiter id, call TestHookWait.suspend with ConnectionHookWaitEnd.cancelled and resolvedValue nil, record the continuation in a store, call resumeConnectionHookWaitRecordedWaiters(), and then call end.throwIfConnectionEnded(). The two copies differ only by the guard condition, the store, and the stored value. A later fix to the cancel or end rules must be made in both copies. Extract one shared private helper in TestHookWait.swift or MCPServer, for example suspendConnectionHookWait(store:guard:record:), that runs the waiter-id allocation, the TestHookWait.suspend call, the record step, and the throwIfConnectionEnded check. Pass the store key path and the early-return and connection-ended conditions as arguments. Call it from both hooks and delete the second copy.
- [x] `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift:600` `duplication/duplication` — suspendUntilStateChange() repeats the body of waitUntilConnectionHookWaitIsRecorded(). Both allocate a waiter id from a counter, increment it, and call TestHookWait.suspend with cancelValue (), resolvedValue returning nil or a value, a record closure that stores the continuation by id, and an end closure that removes and resumes it by id. The two copies differ only by the counter, the store, and the resolvedValue. Any change to the void-wait steps must be made twice. Extract one private helper that takes the store as a WritableKeyPath<MCPServer, [Int: CheckedContinuation<Void, Never>]> and the id counter as a key path, and that runs the shared suspend steps. Let suspendUntilStateChange() and waitUntilConnectionHookWaitIsRecorded() each call it with their own store and their own resolvedValue. Delete the duplicated body.
