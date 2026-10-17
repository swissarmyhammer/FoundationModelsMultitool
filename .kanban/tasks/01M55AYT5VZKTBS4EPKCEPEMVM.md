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