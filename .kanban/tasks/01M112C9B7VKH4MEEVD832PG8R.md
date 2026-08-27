---
assignees:
- claude-code
depends_on:
- 01M112AWZQES72WQT4133593KJ
- 01M112B6G84BBGVNWC28GC8S69
- 01M112BHBVEYK3ZZH0RGQRTXXY
position_column: todo
position_ordinal: '8780'
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
- [ ] A server connects over an in-memory transport and reaches `.ready`, and the `initialize` request carries the elicitation capability with both `form` and `url`.
- [ ] A flaky transport reconnects under `BackoffPolicy`, and a `NonRetryableConnectError` faults at once.
- [ ] `disconnect()` moves the state to `.disconnected`, and `waitUntilReady()` after a fault throws `MCPServerError.notReady`.
- [ ] No symbol of the deleted call design is in this package (grep for `CallWait`, `CallHandle`, `RunningCall`, `get_result` gives nothing).
- [ ] `swift build` succeeds.

## Tests
- [ ] Port `ResilienceTests.swift` and `TransportFactoryTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsMCP/Tests/FoundationModelsMCPTests/` into `Tests/FoundationModelsMultitoolTests/`. Drop the cases that assert on the deleted call design; list each dropped case in the file header with the reason. Add the capability-declaration case.
- [ ] `swift test --filter ResilienceTests` passes.
- [ ] `swift test --filter TransportFactoryTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the actor to make them pass. #eventplan #phase-4