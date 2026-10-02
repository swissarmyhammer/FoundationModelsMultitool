---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3x8p12bejzk447s7mzwa1xw
  text: |-
    Research done.
    - `MCPTestSupport` is only in the root test target. The integration package does not use it. Thus `GatedClock` stays where it is.
    - `MCPServer.init(name:version:clock:clientQueueClock:connectAttemptClock:...)` is internal. Only a `@testable import` reaches it.
    - Root tests that connect with the real connect-attempt clock: the four `MCPTestSupport` connect helpers; direct `MCPServer(name:)` in MCPSessionSweepTests, MCPTracePropagationTests, MetricsTests, MCPServerDiscoveryTests, LostCallTests, LiveCatalogTests, MCPLogRecordTests, TransportFactoryTests, StdioServerProcessTests; `makeLargeCatalogSurface` (target MCPTestServer, used by root OverBudgetSelectionOrderTests and by two integration suites); `CLIRunner.makeDemoRegistry` (production, module MultitoolCLI, used by CLIArgumentTests with a real `mcp-test-server`).
    - No root test outside ResilienceTests needs the timeout to end an attempt. ResilienceTests already gives a GatedClock and opens it.
    - Plan: add `MCPTestSupport.makeServer(...)` with a default `GatedClock()` connect-attempt clock; use it in each helper and each direct site. Give `makeLargeCatalogSurface` and `CLIRunner.makeDemoRegistry` a server-factory parameter whose default is the public initializer (the CLI module cannot call the internal initializer). Root tests pass the gated factory.
    - Note: a GatedClock that no test opens keeps the timeout task of each attempt, and thus its `MCPServer`, alive until the process ends. With the real clock that task lives 10 s. No root test depends on the deinit of an `MCPServer`.
  timestamp: 2026-10-02T02:56:49.739448+00:00
- actor: claude-code
  id: 01m3x99vq8zsj4w2z5mbztjj09
  text: |-
    Implementation landed (not committed).
    - New `MCPTestSupport.makeServer(name:clock:clientQueueClock:connectAttemptClock:callTimeout:renderBudget:elicitationHandler:logger:)`. Its `connectAttemptClock` default is a `GatedClock` that no test opens. It calls the internal initializer.
    - The four connect helpers (`connectedMCPServer(to:over:...)`, `connectedMCPServer(serving:...)`, `connectedLoopbackMCPServer`, `connectedRecordingMCPServer`) take `connectAttemptClock` (default `GatedClock()`) and build through `makeServer`.
    - `ResilienceTests.makeServer` now forwards to the shared factory.
    - Each direct `MCPServer(name:)` in root tests now uses `MCPTestSupport.makeServer`: LiveCatalogTests, LostCallTests, MCPServerDiscoveryTests, MetricsTests, MCPTracePropagationTests, MCPLogRecordTests, MCPSessionSweepTests, TransportFactoryTests, StdioServerProcessTests (`connectServer` and the backoff test).
    - `makeLargeCatalogSurface` (MCPTestServer) takes `makeServer: (String) -> MCPServer`, default the public initializer; root `OverBudgetSelectionOrderTests` passes the gated factory. The integration callers keep the default.
    - Production seam (TDD): `CLIRunner.MCPServerMaker`, `CLIRunner.defaultMakeServer`, and a `makeServer` parameter on `run(...)`, `runDemo`, `makeDemoRegistry` and `startMCPServers`. The CLI module cannot call the internal initializer, so the seam is a factory. New test support `GatedServerMaker` records each server it builds. RED was the compile error "extra argument 'makeServer'"; then GREEN. New tests: `runBuildsEachMCPServerWithTheGivenMaker`, `demoAttachesTheServerTheMakerBuilt`.
    - Discovery: the single-attempt `connect(via:)` arms no timeout. Only `connect(via:backoffPolicy:)` and `reconnect()` (also the reconnect after a fault) race the per-attempt timeout. The gated default covers all of them.
    - Discovery: `replace_all` of the `files` edit op replaced only the first match. Each later site needed its own edit.
    - No test outside ResilienceTests needs the timeout to end an attempt; ResilienceTests already opens its clock and checks `recordedSleeps`.
  timestamp: 2026-10-02T03:07:39.624446+00:00
- actor: claude-code
  id: 01m3x9a36jnwgg9r22fc1ywcs3
  text: |-
    ### implement — changed
    - evidence: 18 source/test files + 1 new (Support/GatedServerMaker.swift). Helpers: MCPTestSupport.makeServer (new), connectedMCPServer(to:over:), connectedMCPServer(serving:), connectedLoopbackMCPServer, connectedRecordingMCPServer; CLIRunner.run/makeDemoRegistry `makeServer` seam; makeLargeCatalogSurface `makeServer`. Tests converted: LiveCatalog, LostCall, MCPServerDiscovery, Metrics, MCPTracePropagation, MCPLogRecord, MCPSessionSweep, TransportFactory, StdioServerProcess, Resilience (forwards), OverBudgetSelectionOrder, CLIArgument (+2 new tests). Runs: `swift test --filter <22 affected suites>` 205 tests / 22 suites passed; root `swift test` 1890 tests / 155 suites passed; `swift build --build-tests --package-path IntegrationTests` OK; `swift test --package-path IntegrationTests --no-parallel --filter 'OverBudgetSurfaceDiscoveryTests|NoDescriptionSurfaceDiscoveryTests|CLISmokeTests'` 4 tests / 3 suites passed. Only build warning: the existing "missing creator for mutated node" of the mlx Cmlx bundle (SwiftPM, not this change).
    - next: /review
  timestamp: 2026-10-02T03:07:47.282219+00:00
position_column: doing
position_ordinal: '80'
title: Pass a gated connect-attempt clock through the MCPTestSupport connect helpers
---
## What
`MCPServer.connectAttemptClock` exists (^tm4x2hp). But `MCPTestSupport.connectedMCPServer(...)` and the helpers that `StdioServerProcessTests` use do not pass it. Thus each connect in these tests races a real 10 s per-attempt timeout. A slow machine can make the connect time out. That is a check of the speed of the machine (decision on ^tm4x2hp and ^kdtrmhv).

## Do
- Give the helpers a `connectAttemptClock` parameter. The default for a test is a clock that does not end (`GatedClock`, as `ResilienceTests.makeServer` does in ^kdtrmhv).
- A test of the timeout gives its own clock, and opens it only after the gated step is in flight (`connectWasCalled` / `makeWasCalled`, added in ^kdtrmhv).

## Acceptance Criteria
- [x] No root test connect depends on the real 10 s connect timeout.

## Tests
- [x] Root `swift test` passes once.