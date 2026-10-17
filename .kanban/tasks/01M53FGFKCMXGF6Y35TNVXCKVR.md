---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53twswe39dxdyze7eqp93rp
  text: |-
    Picked up. Research so far:
    - No call of Task.sleep is in the test target. The only text "Task.sleep" in Tests/ at the card commit 384224d and now is a doc comment in Tests/FoundationModelsMultitoolTests/Support/HangingTransport.swift ("Deliberately not Task.sleep(for:)"). The other sleep calls are on injected clocks (ManualClock in ProviderCooldownTests, the stage clock of DynamicToolsetScenario, the spacing clock of LiveSearchSpacing in IntegrationTests).
    - MCPElicitationTests: elicitationEvent(on:) waits on the recorder with no second event. The call helper call(_:under:whileHolding:under:on:) waits for the arrival of the held call with no second event, and releases the held call only after the second call returns. aWireCompletionUnderAContextCompletesTheFlow waits for the question with no second event. 8 tests connect a server and have no teardown.
    - Unawaited Task in defer: LoopbackHTTPServerTests (4), MCPCapabilityTests (3).
    Next: audit of the rest of Tests/ and IntegrationTests/Tests.
  timestamp: 2026-10-17T02:26:14.542676+00:00
- actor: claude-code
  id: 01m53vp1t5zfgzkvkayajw2yrc
  text: |-
    ### priority change — owner (2026-10-16)
    - The owner set this order: ^179vr1r (a false accept), then ^fcvjb8j, then the card to decline an MCP URL-mode question whose url is not absolute http or https, then this card (T1), then ^1td5bsf.
    - The cards 1, 2 and 3 go in one push when they are reviewed.
    - This card: the current implement step finishes. Then its changes go into a named git stash ("T1 nvxckvr"), so the push of cards 1-3 holds no unreviewed T1 commit. After cards 1-3, apply the stash and continue with test, commit and review.
  timestamp: 2026-10-17T02:40:01.861316+00:00
- actor: claude-code
  id: 01m53vz1j6jadnt5kcsrs7dsm4
  text: |-
    Implementation, part 1 (in the tree, not committed):
    - New Tests/FoundationModelsMultitoolTests/Support/FirstEvent.swift: FirstEvent.start(_:waitingFor:) starts the work and waits for the first of two events (the expected event, or the end of the work). FirstEvent.end(_:) cancels a wait and awaits it.
    - New Tests/Support/MCPTestServer/CountWaiters.swift: one shape for the count waits of ScriptedServer. waitForRecordedNotifications now uses it. New ScriptedServer.waitForElicitationResults(count:) (cancel ends it).
    - RunBindingFixtures: RecordingEventSink.waitUntilElicitationCompleted is now waitUntilElicitationSettled: it also ends on post(elicitationEnded:).
    - MCPElicitationTests: elicitationEvent(on:)/elicitationRequest(on:) are replaced by startEliciting(on:_:) and startElicitingCall(_:on:in:) (first of: elicitation event recorded, or call ends). startHeldHostFlow and startContextURLFlow use FirstEvent. call(_:under:whileHolding:under:on:servedBy:): the arrival wait also ends on the end of the held call (#require arrival); the release of the held call runs on the first of (second call ends, scripted server got the elicitation result), in ensuring, thus on each path. The snippet case of two inner calls does the same. aWireCompletionUnderAContextCompletesTheFlow uses startContextURLFlow and waitUntilElicitationSettled. 11 tests that had no teardown now use withConnection (withConnection now calls ensuring). aRequestAfterTheServerIsGone disconnects the client in ensuring.
    - The 7 `defer { Task { ... } }` teardowns (LoopbackHTTPServerTests 4, MCPCapabilityTests 3) and 2 MCPCapabilityTests tests with no disconnect use ensuring now. No `defer { Task` is left in Tests/ or IntegrationTests/Tests.
    - Task.sleep: no call is in Tests/ or IntegrationTests/Tests, also not at the card commit 384224d. The one match is a doc comment of HangingTransport.swift that tells why the double does not use Task.sleep. No change.
    Mutation check: theSessionAnswerReachesTheTool called echo (no question) one time. Result: the test failed in 0.031 s with "the work ended before the run recorded an elicitation event" on .inMemory and .http (before the change, that wait had no end). The mutation is reverted.
    Known waits in MCPElicitationTests that stay: aCancelDuringTheWaitEndsIt awaits the wait that it cancelled (the event under test; a second event, a hold, would race the cancel). aCancelEndsTheWaitForTheHold hangs only when the cancel and the hold both fail.
    Test: swift test, one run: "Test run with 2437 tests in 211 suites passed", exit 0. IntegrationTests: swift build --build-tests, exit 0.
  timestamp: 2026-10-17T02:44:56.518134+00:00
- actor: claude-code
  id: 01m53vzrazmhza7ff9knyacgys
  text: |-
    Blocker: the scope of "search the whole test target for the same cause" is much larger than the known cases. Four read-only audits (2026-10-17) found these T1 cases that are still open:
    1. MCP test files (Tests/FoundationModelsMultitoolTests): 115 WAIT, 113 FIXTURE. FIXTURE: about 100 tests connect an MCPServer and never disconnect (MCPToolTests 15, MCPServerCallTests 11, ScriptedServerSelfTests 11 disconnect only on success, ResilienceTests 8, SurfaceRefresherTests 8, LiveCatalogTests 6, RegistryRebuildTests 5, MCPTracePropagationTests 5, MCPServerDiscoveryTests 4, StdioServerProcessTests 10 child processes, MCPSessionSweepTests 4, others). WAIT: gate/arrival/sleeper waits with no race against the end of the call (ResilienceTests 17, SurfaceRefresherTests 17, LiveCatalogTests 17, ScriptedServerSelfTests 8, MCPServerCallTests 7, RegistryRebuildTests 5, MCPSessionSweepTests 5, DropObservingTransportTests 4, StdioServerProcessTests 4, others).
    2. Other unit test files: about 150 WAIT (JSCInterpreterTests 12 plus 21 callers of its run helper, OutputChunkStreamTests 13, RunCodeToolTimeoutTests 12, BackgroundSettleGraceTests 9, SandboxGlobalsTests 8, ShellSessionSweepTests 8, MultiToolExecutionTests 7, HardeningTests 6, ShellRunnerTests 6, SuspendedContextTests 5, others), and FIXTURE: 9 unawaited `defer { runTask.cancel() }` of live child processes in ShellRunnerTests, temp dirs with no owner (TestSupport.makeTemporaryDirectory, about 33 files; the multitool-stub-<ULID> dirs of StubRouterFixtures), MCP servers with no disconnect (MetricsTests, TransportFactoryTests, BuilderSurfaceTests, WebCapabilityTests, OverBudgetSelectionOrderTests, TelemetryContentSafetyTests).
    3. Shared helpers with no cancel handler and no second event ("deaf" waits): ReleaseGate.wait (one slot), Rendezvous.arrive, ProcessExitWait.waitUntilGone, SessionOutputLog.wait/runMail/deliveredRunMail, ConcurrencyGate.acquire/waitForWaiters, LoopbackHTTPServer.waitUntilServingEventStream, waitForDynamicToolsetStages, ScenarioGate.waitForWaiter, ManualRunClock.waitForSleepers (Extras), ShellState.waitForStoredLines, MCPServer.waitUntilTransportDropped and waitUntilToolListChangedGeneration (product test hooks), SurfaceRefresherTests.waitUntil, LiveCatalogTests.waitForSnapshots.
    4. IntegrationTests/Tests: 24 cases (ShellBackgroundRunner 6, ScenarioRunner 4, LiveRouterFixture turnstile acquire, ProcessExitWait, 6 temp dirs with no owner, 4 MCP servers with no disconnect, LiveSearchSpacing real-clock spacing for live web services).
    About half of the WAIT cases have no second event that a test can see: the wait is for the event under test (for example a notification that the code under test must send, a kill that must end a process, a cancel that must end a wait). For these, T1 needs a decision: a new product or helper hook (for example a barrier, or a wait that also ends on the end of the stream or the session), or a list of known T1 exceptions, as Agents did (^6w3yneh).
    Question for a person: (a) do all of the open cases in this card (about 450 edits, with the hook design for the cases with no second event), or (b) close this card with the known cases and the shared helpers, and split the rest into new cards by file group (MCP fixtures; MCP waits; shell and process waits; JSC and runCode waits; shared deaf helpers; temp dirs; IntegrationTests), with a decision on the exception list?
  timestamp: 2026-10-17T02:45:19.839272+00:00
- actor: claude-code
  id: 01m53vzvn5f37gp3c86z57bwqf
  text: |-
    ### implement — stuck
    - evidence: changed (not committed): Tests/FoundationModelsMultitoolTests/MCPElicitationTests.swift, LoopbackHTTPServerTests.swift, MCPCapabilityTests.swift, Fixtures/RunBindingFixtures.swift, new Support/FirstEvent.swift; Tests/Support/MCPTestServer/ScriptedServer.swift, new CountWaiters.swift. Mutation check: the elicitation wait fails at once (0.031 s), it does not hang. swift test: 2437 tests in 211 suites passed, exit 0. IntegrationTests swift build --build-tests: exit 0.
    - gap: about 450 T1 cases in the rest of Tests/ and IntegrationTests/Tests are open (see the blocker comment). About half have no second event that a test can see.
    - next: a person decides (a) all in this card, or (b) split into new cards and decide on an exception list.
  timestamp: 2026-10-17T02:45:23.237282+00:00
- actor: claude-code
  id: 01m53w24vdxhhqd902ba835463
  text: |-
    ### decision — owner chose option (b) (2026-10-16)
    - This card closes with the work in git stash "T1 nvxckvr" (MCPElicitationTests waits and teardowns; no `defer { Task` left in Tests/ or IntegrationTests/Tests). Apply and commit it after cards ^179vr1r, ^fcvjb8j and the URL-decline card are pushed, or in the same batch.
    - The rest (about 450 cases, list in the comments of this card) is split into 7 cards by group, in this order: 1) the 14 shared helpers; 2) MCP fixtures (servers never disconnected); 3) MCP waits; 4) shell and process waits; 5) JSC and runCode waits; 6) temp folders and other fixture leaks; 7) IntegrationTests. One more card holds the exception list.
    - Exception rule: first look for a second event that already exists (the call ends, the transport closes, the child process exits, the stream finishes). A wait for a notification can nearly always also end on the close of its transport or the end of its call. A test-only hook in a test helper is permitted. Put a wait on the list only when no such event exists without a production change. Do not change production code only to add a test hook; bring such a case to the owner.
  timestamp: 2026-10-17T02:46:38.189513+00:00
depends_on:
- 01M53FGDHZJ8BFKNZGKK4K5V9R
position_column: doing
position_ordinal: '8180'
title: 'Test rule T1: each wait in a test also ends on the failure event, and fixtures close when the body throws'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), new test rule T1.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits. Fixtures close also when the test body throws.

Known cases:
- MCPElicitationTests about lines 767-771: if the second call never returns, held.release() never runs.
- elicitationRequest(on:) about line 346.
- `defer { Task { await server.disconnect() } }` (about lines 782, 799, 817, 839) is not awaited.

Search the whole test target for the same cause. One Task.sleep is left in the test target; remove it.

No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes