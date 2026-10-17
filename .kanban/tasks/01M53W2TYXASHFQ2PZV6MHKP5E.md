---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m547skskfwk5k89c40jdamkv
  text: |-
    Picked up. Research:
    - `ensuring(_:after:)` is a shared function in Fixtures/StubRouterFixtures.swift. withConnection(of:_:) was private in MCPElicitationTests.swift.
    - New shared file Tests/FoundationModelsMultitoolTests/Support/MCPConnectionScope.swift: protocol Disconnectable (Actor, `disconnect() async`), conformances of MCPServer and MCP.Client, and MCPTestSupport.withConnection(of:_:) (one generic helper over Disconnectable; it calls ensuring). The private copy in MCPElicitationTests is removed.
    - A raw `any Transport` cannot conform (Transport is a protocol of the MCP module), thus a test of a raw transport uses the shared `ensuring` directly.
    - Tool note: the sah files `edit file` with replace_all changes only the first match. One call for each occurrence is necessary.
    - Work is split in 4 forks by file group (A: elicitation rename, capability, loopback, tool, catalog, server mode; B: call, self tests, discovery, sweep, trace, log record, lost call, drop observing; C: resilience, refresher, live catalog, rebuild; D: stdio, transport factory, metrics, builder, web, over budget, telemetry, journal op). The waits (groups 3 and 4) are not changed here.
  timestamp: 2026-10-17T06:11:41.491245+00:00
- actor: claude-code
  id: 01m548f5w2fbr35bv67mdm6nf7
  text: |-
    Implementation landed (in the tree, not committed).
    - Shared helper: Tests/FoundationModelsMultitoolTests/Support/MCPConnectionScope.swift. protocol Disconnectable (Actor), MCPServer and MCP.Client conform, MCPTestSupport.withConnection(of:_:) calls the shared ensuring. The private withConnection of MCPElicitationTests is removed; its 31 calls use the shared helper. The inline `ensuring({ await server.disconnect() })` of MCPCapabilityTests (5) and `ensuring({ await client.disconnect() })` of LoopbackHTTPServerTests (1) and MCPElicitationTests (1) use the shared helper now.
    - Tests changed: MCPToolTests 15, MCPServerCallTests 12, ScriptedServerSelfTests 12, StdioServerProcessTests 16, ServerModeTests 9 (through the helper registeredTools), ResilienceTests 9, RegistryRebuildTests 5, LiveCatalogTests 7, SurfaceRefresherTests 8 (through withConnectedServer and makeGround(over:)), MCPTracePropagationTests 6, MCPServerDiscoveryTests 5, MCPSessionSweepTests 4 (withGround), OverBudgetSelectionOrderTests 4 (withOverBudgetSurface), MCPCapabilityTests 5, MetricsTests 3, TransportFactoryTests 3, MCPLogRecordTests 2, LostCallTests 2, RegisteredJournalOpTests 2, LoopbackHTTPServerTests 1, BuilderSurfaceTests 1, WebCapabilityTests 1, TelemetryContentSafetyTests 1.
    - Extra: two gated tests of ResilienceTests open the disconnect gate in an inner ensuring, thus no disconnect stays parked at the gate when the body throws. Three held-tool tests of MCPServerCallTests release the held call in ensuring.
    - Not changed, with the reason: tests where the connect must fail or never runs (for example connectThrowsTypedErrorNamingServerIdentityWhenExhausted, stateBecomesFaultedOnConnectFailure, failedConnectLogsEachAttemptAndTheEnd, factoryThatAlwaysThrowsExhaustsBackoffAndHardFails), tests where the teardown is the action under test (disconnectEndsAStragglerWhoseConnectNeverReturns, aServerThatNeverReachesReadyThrowsNotReady), releasingEveryReferenceReapsTheProcessViaOwnerTeardown (a cleanup closure would keep the process alive), DropObservingTransportTests (raw transports, already closed on each path), MCPToolCatalogTests and LogReadbackFixtures (no connect).
    - Waits (T1 groups 3 and 4) are not changed. `defer { recording.task.cancel() }` in LiveCatalogTests stays (a task, not a server).
    - No `defer { Task` in Tests/ or IntegrationTests/Tests. No production file changed. No IntegrationTests file changed, thus no build there.
    - swift build --build-tests: exit 0, only the toolchain line "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
    - swift test, one full run: exit code 0, "Test run with 2449 tests in 212 suites passed after 5.225 seconds."
  timestamp: 2026-10-17T06:23:28.130348+00:00
- actor: claude-code
  id: 01m548f7rark02g5gx0t298wbv
  text: |-
    ### implement — changed
    - evidence: 24 test files changed and 1 new file (Support/MCPConnectionScope.swift, shared helper MCPTestSupport.withConnection(of:_:)). About 133 tests changed. swift test, one full run: exit code 0, 2449 tests in 212 suites passed.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T06:23:30.058594+00:00
- actor: claude-code
  id: 01m548jdfzcjfcq40thbc8b2tr
  text: |-
    ### test - green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing summary: "Test run with 2449 tests in 212 suites passed after 9.240 seconds." XCTest part: 0 tests, 0 failures.
    - no failure. No skipped test. No compiler warning in the output.
    - one build-system line: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle path in .build. It comes from the SwiftPM build system for a dependency bundle. It is not in project source.
    - next: review.
  timestamp: 2026-10-17T06:25:14.239132+00:00
- actor: claude-code
  id: 01m548ka6tsyr0k4ca9qgr0fzn
  text: |-
    ### commit — changed
    - evidence: e579ead test: close each MCP test server and client also when the test throws
    - next: review
  timestamp: 2026-10-17T06:25:43.642793+00:00
- actor: claude-code
  id: 01m549f8xhbzkn5dpy5e5mrrbd
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit e579ead). 3 findings (3 confirmed, 29 refuted). Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:277, Tests/FoundationModelsMultitoolTests/ResilienceTests.swift:795, Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift:374.
    - scope: All 3 findings are on lines that this commit changed. No finding is about a wait with no second event. Thus no finding goes to ^c1v08m3 or ^8y8htqx.
    - next: Do the 3 items in the "Review Findings (2026-10-17 01:26)" section. Then do a new review. The task stays in review.
  timestamp: 2026-10-17T06:40:59.825499+00:00
- actor: claude-code
  id: 01m549gem7wjrazsa366ad11sh
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 25 files (one shared MCPTestSupport.withConnection(of:_:); about 133 tests disconnect on both paths)
    - test: green — swift test, exit 0, 2449 passed, 0 failed, 0 skipped
    - commit: e579ead
    - review: findings — Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:277; ResilienceTests.swift:795; ScriptedServerSelfTests.swift:374
  timestamp: 2026-10-17T06:41:38.439062+00:00
- actor: claude-code
  id: 01m549z578mtyxpj2w4ymapqv6
  text: |-
    Picked up the 3 findings of "Review Findings (2026-10-17 01:26)". Research:
    - Finding 2: in explicitConnectDuringInFlightReconnectWins the reconnect ALWAYS throws by design. It has one attempt (singleAttempt), the attempt hangs, and its timeout ends it. Then connect(via:backoffPolicy:) throws MCPServerError.backoffExhausted(serverName:attempts:lastError:). Thus a bare `try await reconnect.value` fails the test each time. The fix keeps the error with `try await` and checks it is backoffExhausted for this server with one attempt (the same do/catch shape as connectThrowsTypedErrorNamingServerIdentityWhenExhausted). Each other error, and no error, fails the test.
    - Finding 3: MCP.Client.disconnect() resumes each pending request with MCPError.internalError("Client disconnected"). The message loop end does not fail a pending request, thus the error is fixed. MCPError is not Equatable (transportError holds an Error), thus the check is a catch pattern.
    - Same cause, other sites in the files of e579ead: held tool released on success only (MCPSessionSweepTests native test, ScriptedServerSelfTests cancelledNotificationRecording, RegisteredJournalOpTests anMCPVerbCarriesThePairIntoItsOwnCall), gates of ResilienceTests released on success only (late attempt tests, straggler tests, factory test, gatedConnect of the fresh connect test), `try?` that hides a result (ResilienceTests disconnectWaitsForTheFactoryOfAPendingAttempt: the stale attempt returns with no error; StdioServerProcessTests openFileDescriptorCount: -1 sentinel; ScriptedServerSelfTests scheduled mutation trigger), "any Error" checks with a known error (MCPTracePropagationTests reconnect: MCPError.internalError "Client disconnected"; LiveCatalogTests and MCPServerDiscoveryTests flaky connect: MCPError.connectionClosed; MCPServerDiscoveryTests dangling schema: GenerationSchema.SchemaError; StdioServerProcessTests killed child: MCPError.transportError).
    - Not changed: the `try?` in MCPElicitationTests `awaiting:` closures (a `#require` on the gate follows each one), `try? await heldEnd.pass()` (documented: a cancel lets the end go on).
  timestamp: 2026-10-17T06:49:40.328502+00:00
- actor: claude-code
  id: 01m54abpj29rbdb14tv5nj384v
  text: |-
    Findings implemented (in the tree, not committed). All 3 items are checked.
    - Finding 1: MCPSessionSweepTests parked test and native test release the held call in an `ensuring` around the withStubRun body.
    - Finding 2: ResilienceTests explicitConnectDuringInFlightReconnectWins uses `Task { try await server.reconnect() }` and awaits `reconnect.value` with `try`. By design that reconnect throws (one attempt, ended by its timeout), thus the test checks the exact error: new helper expectBackoffExhausted(after:from:) checks MCPServerError.backoffExhausted for this server with one attempt. Each other error, and no error, fails the test. connectThrowsTypedErrorNamingServerIdentityWhenExhausted uses the same helper now (the same do/catch before).
    - Finding 3: ScriptedServerSelfTests transportDropMidCall checks MCPError.internalError with the detail "Client disconnected". Shared helpers in Support/MCPConnectionScope.swift: MCPTestSupport.expectMCPError(named:from:matching:) (reuses MCPCallProbe.thrownError), expectClientDisconnected(_:), expectConnectionClosed(_:), and the constant clientDisconnectedDetail.
    - Same cause in the other files of e579ead: held call released in `ensuring` (ScriptedServerSelfTests cancelledNotificationRecording, RegisteredJournalOpTests anMCPVerbCarriesThePairIntoItsOwnCall); gates of ResilienceTests opened in `ensuring` (lateResolvingAttemptAfterExhaustionIsDiscarded, lateFailingAttemptAfterExhaustionIsDiscarded, lateResolvingFactoryAfterExhaustionDisposesAbandonedTransport, aStragglerThatEndsAfterTheRetryLeavesTheConnectionOfTheRetry, disconnectEndsAStragglerWhoseConnectNeverReturns, disconnectWaitsForTheFactoryOfAPendingAttempt, and the connect gate of freshConnectIsNotBlockedByADisconnectWhoseTransportHangs); `try?` removed (disconnectWaitsForTheFactoryOfAPendingAttempt now uses `try await connecting.value`: the stale attempt returns with no error; StdioServerProcessTests openFileDescriptorCount now throws, no -1 sentinel; ScriptedServerSelfTests scheduled trigger records an issue when its wait throws); "any Error" checks replaced with the known error (MCPTracePropagationTests reconnectRecordsASpanEvent: "Client disconnected"; LiveCatalogTests failedReconnectEmitsFaultedSnapshot and MCPServerDiscoveryTests stateBecomesFaultedOnConnectFailure: MCPError.connectionClosed; MCPServerDiscoveryTests identityRemainsNilWhenDiscoveryFailsAfterSuccessfulHandshake: GenerationSchema.SchemaError; StdioServerProcessTests killingTheChildExternallySurfacesAsAThrownErrorAndNotASignal: MCPError.transportError).
    - Not changed, with the reason: the `try?` in MCPElicitationTests `awaiting:` closures (a `#require` on the gate follows each one, thus the failure is seen); `try? await heldEnd.pass()` in MCPElicitationTests (documented: a cancel lets the end go on); waitUntilReadyReturnsOnceAGatedConnectCompletes (no statement that can throw comes before its release).
    - No production file changed. No IntegrationTests file changed.
    - swift build --build-tests: exit 0, only the build-system line "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
    - swift test, one full run: exit code 0. "Test run with 2449 tests in 212 suites passed after 3.283 seconds." XCTest: 0 tests, 0 failures.
  timestamp: 2026-10-17T06:56:31.298473+00:00
- actor: claude-code
  id: 01m54abvwh6h1a8qx7ept6m0f8
  text: |-
    ### implement — changed
    - evidence: 11 test files changed (MCPSessionSweepTests, ResilienceTests, ScriptedServerSelfTests, RegisteredJournalOpTests, MCPTracePropagationTests, LiveCatalogTests, MCPServerDiscoveryTests, StdioServerProcessTests, Support/MCPConnectionScope.swift). Findings checked 3/3. swift test, one full run: exit code 0, 2449 tests in 212 suites passed.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T06:56:36.753649+00:00
- actor: claude-code
  id: 01m54acarascr2q97adxkxt78h
  text: |-
    ### implement — changed
    - evidence: correction of the record above: 9 test files changed, not 11 (git status): LiveCatalogTests, MCPServerDiscoveryTests, MCPSessionSweepTests, MCPTracePropagationTests, RegisteredJournalOpTests, ResilienceTests, ScriptedServerSelfTests, StdioServerProcessTests, Support/MCPConnectionScope.swift. Findings checked 3/3. swift test, one full run: exit code 0, 2449 tests in 212 suites passed, 0 failed.
    - next: review. The task stays in doing.
  timestamp: 2026-10-17T06:56:51.978084+00:00
- actor: claude-code
  id: 01m54aebeh62mg7xc48ysgr491
  text: |-
    ### test — green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing: "Test run with 2449 tests in 212 suites passed after 3.719 seconds." No warning and no error lines in the output. No test is skipped.
    - next: review
  timestamp: 2026-10-17T06:57:58.225843+00:00
- actor: claude-code
  id: 01m54af18b8ma8at3t3n266dn0
  text: |-
    ### commit — changed
    - evidence: b175701 test: release held calls in ensuring and check the known error
    - next: none
  timestamp: 2026-10-17T06:58:20.555436+00:00
- actor: claude-code
  id: 01m54ar2d0kvza00r4jxp1cgne
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit b175701). 9 files reviewed. 2 .kanban files not reviewed (ignore rule). Counts: findings 0, confirmed 0, refuted 1, attempted 14, failed 0. All 3 items in "Review Findings (2026-10-17 01:26)" are checked.
    - finding 2 (ResilienceTests.swift reconnect): the task uses `try await server.reconnect()`. expectBackoffExhausted(after:from:) awaits the value with try. It checks that the error is MCPServerError.backoffExhausted for this server with one attempt. A different error or no error records an issue. Thus a reconnect failure is not hidden. This satisfies the finding.
    - next: none. The task is in done.
  timestamp: 2026-10-17T07:03:16.640295+00:00
- actor: claude-code
  id: 01m54arq0q26409x2ypftxvw9r
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 9 files (3 of 3 findings fixed; held calls released in ensuring; known errors checked; expectBackoffExhausted helper)
    - test: green — swift test, exit 0, 2449 passed, 0 failed, 0 skipped
    - commit: b175701
    - review: clean — 0 findings
  timestamp: 2026-10-17T07:03:37.751674+00:00
depends_on:
- 01M53W296FG93NMJT89T9DC8NB
position_column: done
position_ordinal: ffffff9780
title: 'T1 group 2: MCP test fixtures — servers that are never disconnected'
---
Split from ^nvxckvr (test rule T1). The list (most of the about 230 cases in the MCP test files other than MCPElicitationTests) is in the comments of ^nvxckvr.

Rule T1: fixtures close also when the test body throws.

Do: each MCP test that connects a server disconnects it on both paths, awaited. Use the shared awaited helper (withConnection(of:_:) / ensuring, from ^etqn9dn and ^nvxckvr) or move it to a shared test support file. No `defer { Task { ... } }`. Keep the checks of each test the same.

No .timeLimit, sleep, poll or retry. Do not delete a test. Do not change production code only to add a test hook: bring such a case to the owner. One full run. #elicitation-fixes #t1

## Review Findings (2026-10-17 01:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 25 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift:277` `completeness/invariant-propagation` — The held tool is released only on the success path of parkedCallGetsTheAdvisoryCancelAndCancelledBeforeTheTransportCloses. If an assertion or the run throws before line 277, the gate stays closed. The same change wraps the server in withConnection to close it on throw, but does not release the held call on throw. The sibling tests use ensuring for this. Move the release into an ensuring block around the withStubRun body, the same way MCPServerCallTests does. Do this so the release runs on both the success path and the throw path.
- [x] `Tests/FoundationModelsMultitoolTests/ResilienceTests.swift:795` `test-integrity/no-test-cheating` — The reconnect task discards its error with `try?`. If the reconnect fails, the test does not see the failure. Only the final state is checked, so a failed reconnect can pass the test. Keep the error. Use `try await server.reconnect()` inside the task and await its value with `try`, so a thrown error fails the test.
- [x] `Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift:374` `test-integrity/no-test-cheating` — The assertion accepts any error type. The comment says the test proves the drop stopped the answer, but any failure, including an unrelated decoding or encoding error, would also pass. This weakens the check that the call was left unanswered. Assert the specific error the disconnect produces, such as the "Client disconnected" MCPError case, so an unrelated failure cannot satisfy the test.
