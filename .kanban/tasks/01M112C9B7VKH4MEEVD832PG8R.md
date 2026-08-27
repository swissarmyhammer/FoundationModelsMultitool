---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m11sqxx50q711cz5eqpp88sp
  text: |-
    ### Discoveries during the port

    - The source `MCPServer.swift` (4,525 lines) mixes the connection half with the call path. The connection half stands in this package as three files: `MCPServer.swift` (the actor, its state, `init`, `waitUntilReady()`), `MCPServer+Connection.swift` (the four `connect(via:)` forms, `disconnect()`, `reconnect()`, the retry loop, the generation guard, the handler registration) and `MCPServer+ClientQueue.swift` (the FIFO queue over `client.connect` and `client.disconnect`). `BackoffPolicy.swift` holds `BackoffPolicy`, `TransportFactory` and `MCPServerError`; `SingleResume.swift` holds the one-resumption race both extensions use.
    - The source reconnected from inside the call path (`reconnectAfterFault()`), which this package does not port. The reconnect stands as the public `reconnect()`: it calls the retained factory again under the retained policy. `MCPServerError.neverConnected` is new: `reconnect()` throws it when no connect ever ran. Without `reconnect()`, `transportFactory` and `activeBackoffPolicy` would be assign-only properties.
    - The card says `disconnect()` moves the state to `.disconnected`. `MCPServerState` from the catalog task had no such case, and its doc said there is none. The case is added, and `disconnect()` bumps the connect generation, so a straggler attempt cannot move a disconnected server back to `.ready`.
    - `MCPServer.init(name:version:clock:renderBudget:logger:)` builds the `MCP.Client` with `Elicitation(form: .init(), url: .init())`. `name` is both the client name sent at `initialize` and the identity a successful connect establishes. `RenderBudget`, `MCPServerState` and `ServerIdentity` became `public`, because the public `init` and the public `state` name them.
    - `ScriptedServer.start(transport:)` now installs the initialize hook of `MCP.Server` and records `receivedClientCapabilities`, so a test proves the wire carried the capability, and not only that the client held it.
    - The source registered three notification handlers. The `progress` handler belongs to the deleted call path. The `elicitation/complete` handler belongs to the elicitation task. The `tools/list_changed` handler is registered once per actor and logs the notification; the discovery task adds the coalesced re-list.
    - No `.swift-format` or `.swiftlint.yml` file is in the repository. The new files follow the 4-space, 100-column style of the folder.
    - The test target already holds a `CallCounter` (`Fixtures/AgentSessionFixtures.swift`); the ported suites reuse it. The three gated doubles of the source shared one gate shape and one delegation shape; here `ReleaseGate` and the `WrappingTransport` protocol hold each one time.
    - `connectedServer(to:over:clientName:capabilities:)` keeps its `MCP.Client` return, because `ServerModeTests` and `ScriptedServerSelfTests` drive the wire directly. `connectedMCPServer(to:over:name:)` is the new helper that returns a connected `MCPServer`.
  timestamp: 2026-08-27T14:24:50.085051+00:00
- actor: claude-code
  id: 01m11srmdtf8pqjj3t5dtyr5ke
  text: |-
    ### implement — changed
    - evidence: 24 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift, MCPServer+Connection.swift, MCPServer+ClientQueue.swift, BackoffPolicy.swift, SingleResume.swift (new); MCPServerIdentity.swift, RenderBudget.swift, TransportContracts.swift, MCPCapability.swift (edited); Tests/Support/MCPTestServer/ScriptedServer.swift (edited); Tests/FoundationModelsMultitoolTests/ResilienceTests.swift, TransportFactoryTests.swift, Support/ManualClock.swift, Support/ReleaseGate.swift, Support/WrappingTransport.swift, Support/GatedConnectTransport.swift, Support/GatedDisconnectTransport.swift, Support/GatedTransportFactory.swift, Support/DisposableSpyTransport.swift, Support/HangingTransport.swift, Support/RespawningTransport.swift (new); StdioServerProcessTests.swift, Support/MCPTestSupport.swift (edited). `swift build` clean; `swift test --filter 'ResilienceTests|TransportFactoryTests|StdioServerProcessTests'` — 40 tests in 3 suites pass; `rg "CallWait|CallHandle|RunningCall|get_result" Sources Tests` gives nothing.
    - next: the `test` step runs the whole suite, then `commit`, then `review`.
  timestamp: 2026-08-27T14:25:13.146308+00:00
- actor: claude-code
  id: 01m11ssd70q3fgy6a53cr4x7ak
  text: |-
    ### test — green
    - evidence: `swift test` — 1188 tests in 85 suites passed, 0 failed, 0 skipped; `swift build --build-tests` reports no compiler warning.
    - next: commit.
  timestamp: 2026-08-27T14:25:38.528875+00:00
- actor: claude-code
  id: 01m11sst88w2jtcsaxwt2z5h18
  text: |-
    ### commit — changed
    - evidence: f284fcd feat(mcp): port the MCPServer connection lifecycle
    - next: review HEAD~1..HEAD.
  timestamp: 2026-08-27T14:25:51.880676+00:00
- actor: claude-code
  id: 01m11t8mfw8hq00myj2d8eby11
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (f284fcd) — 0 findings, 14 validator runs attempted, 0 failed; 23 files reviewed, 2 `.kanban/` files excluded by `.reviewignore`. No prior finding on the card.
    - next: the task moves to done.
  timestamp: 2026-08-27T14:33:57.500971+00:00
- actor: claude-code
  id: 01m11t8qyk4039azc6h2h4s16w
  text: |-
    ### finish iteration 1 — review clean, task done
    - implement: changed — 24 files; the connection half of `MCPServer` ported across `MCPServer.swift`, `MCPServer+Connection.swift`, `MCPServer+ClientQueue.swift`, `BackoffPolicy.swift`, `SingleResume.swift`; `ResilienceTests`, `TransportFactoryTests` and the test doubles ported; `StdioServerProcessTests` gains its three deferred cases.
    - test: green — `swift test` 1188 tests in 85 suites passed, 0 failed, 0 skipped, no compiler warning.
    - commit: f284fcd
    - review: clean — 0 findings on HEAD~1..HEAD.
  timestamp: 2026-08-27T14:34:01.043950+00:00
depends_on:
- 01M112AWZQES72WQT4133593KJ
- 01M112B6G84BBGVNWC28GC8S69
- 01M112BHBVEYK3ZZH0RGQRTXXY
position_column: done
position_ordinal: ff9080
title: 'Port MCPServer connection lifecycle: connect, backoff, state'
---
## What
Port the connection half of `MCPServer`: connect, disconnect, backoff and reconnect, the transport factory, the state machine, and `waitUntilReady()`. Discovery and the live catalog come in the next task. Do NOT port the call path: a later task rewrites it onto Router's run plane.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift` (4,525 lines). The parts to port here: lines 61–460 (`BackoffPolicy`, `MCPServerError`, `TransportFactory`, `NonRetryableConnectError`, `DisposableTransport`), the actor's connection state and `init`, `connect(via:)` in its four forms, `disconnect()`, `waitUntilReady()`, and `setupHandlers()` (line 3214) without its elicitation registration (`declareElicitationCapabilityAndRegisterHandler(coordinator:)`, line 3709, belongs to the elicitation task).
- Leave out, for good: `CallWait`, `CallDeadline`, `CallHandle`, `RunningCall`, `HardenedCallOutcome`, `MCPCallRecord`, `MCPRunningCallRecord`, `MCPCallTools` (the `get_result` / `list_calls` / `cancel_call` follow-up tools), `MCPToolOperationEvents`, `callOutcomes`, `progressUpdates`, `includeCallFollowUpTools`, `maxRetainedSettledCalls`, `maxRetainedCallRecords`, `operationProgressThrottleInterval`, `defaultWait`, `foundationModelsTools()`, `MCPToolProvider`, and `resolveSessionTools`. eventplan.md § "Consolidation of the siblings": "We delete the two local designs."
- Target: `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift` and `MCPServer+Connection.swift`. Split the actor with extensions in files by concern, the way `RoutedSessionActor*.swift` does in Router. No file over 1,000 lines.
- **`MCPServer` constructs its own `MCP.Client`.** In swift-sdk 0.12.1 client capabilities are fixed at `Client.init(name:version:capabilities:)` and sent verbatim in `initialize`; nothing can add one at connect. And `Client.Capabilities.Elicitation.init(form:url:)` defaults `url` to `nil`, so URL-mode elicitation is off unless declared. Thus `MCPServer.init(name:version:clock:renderBudget:logger:)` builds the `Client` itself with `Elicitation(form: .init(), url: .init())`. Do not take a `Client` from the host. Keep a `@testable` path for a test to inspect the client.
- Logging with `os.Logger`. `ServerIdentity` and `MCPServerState` come from the catalog task.
- `MCPServer` is public, because a host constructs and connects it before `buildRegistry()`. The elicitation handler registration is added by the elicitation task.

## Acceptance Criteria
- [x] A server connects over an in-memory transport and reaches `.ready`, and the `initialize` request carries the elicitation capability with both `form` and `url`.
- [x] A flaky transport reconnects under `BackoffPolicy`, and a `NonRetryableConnectError` faults at once.
- [x] `disconnect()` moves the state to `.disconnected`, and `waitUntilReady()` after a fault throws `MCPServerError.notReady`.
- [x] No symbol of the deleted call design is in this package (grep for `CallWait`, `CallHandle`, `RunningCall`, `get_result` gives nothing).
- [x] `swift build` succeeds.

## Tests
- [x] Port `ResilienceTests.swift` and `TransportFactoryTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Drop the cases that assert on the deleted call design; list each dropped case in the file header with the reason. Add the capability-declaration case.
- [x] `swift test --filter ResilienceTests` passes.
- [x] `swift test --filter TransportFactoryTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the actor to make them pass. #eventplan #phase-4