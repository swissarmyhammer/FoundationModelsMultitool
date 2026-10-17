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
depends_on:
- 01M53W296FG93NMJT89T9DC8NB
position_column: doing
position_ordinal: '8180'
title: 'T1 group 2: MCP test fixtures — servers that are never disconnected'
---
Split from ^nvxckvr (test rule T1). The list (most of the about 230 cases in the MCP test files other than MCPElicitationTests) is in the comments of ^nvxckvr.

Rule T1: fixtures close also when the test body throws.

Do: each MCP test that connects a server disconnects it on both paths, awaited. Use the shared awaited helper (withConnection(of:_:) / ensuring, from ^etqn9dn and ^nvxckvr) or move it to a shared test support file. No `defer { Task { ... } }`. Keep the checks of each test the same.

No .timeLimit, sleep, poll or retry. Do not delete a test. Do not change production code only to add a test hook: bring such a case to the owner. One full run. #elicitation-fixes #t1