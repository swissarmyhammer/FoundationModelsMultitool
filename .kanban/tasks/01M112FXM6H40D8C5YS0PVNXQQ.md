---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12k9dcj3734t5ag4tdzm0jp
  text: |-
    ### Research and discoveries

    - `ShellState` has no `close()` and no `deinit`. The shell store is released with the session by ARC. No host in this package calls `RoutedSession.close()`, thus there is no code hook for step 2 to wire into. The pool is the MCP side of that release: the host holds `builder.serverPool` and calls `shutdownAll()` after `RoutedSession.close()`. The doc comments of `MCPServerPool` and `Builder.serverPool` state this route.
    - The first test run (red) showed two gaps that the design did not show:
      1. `MCPServer.call` started the `notifications/cancelled` in a detached `Task` from its `onCancel` handler. A `disconnect()` that ran first failed the call as `.lost` before that task ran, and the notice never reached the wire. Fix: `CancellationNotices` holds each notice task, and `disconnect()` drains the ledger before it tears the client down.
      2. In the parked shape, the cancellation of the `runCode` run reached the inner `tools.*` call only on the next poll of the JS promise pump (20 ms). The sweep returned before that, and the pool closed the transport first. Fix: `InFlightInnerCalls` holds each inner call of one `runCode` invocation in a task, and the cancellation handler of `MultiTool.run` cancels every one of them at once, in the same `cancel()`.
    - The second fix made a cancelled call able to finish with a value or a repairable error before the watchdog read the flag (`HardeningTests` and `SuspendedContextTests` went red). `MultiTool.runCapturingOutcome` now answers `CancellationError` for a cancelled call whatever the snippet did, which is what `call(arguments:)` documents.
    - The order "advisory cancel, then the terminal `.cancelled`" of the parked shape is not fixed by this package: Router's cooperative canceler returns at once and `SessionMailbox.sweep()` synthesizes the terminal, while the notice goes out from its own task. The tests assert the two orders this package fixes: the advisory cancel is on the wire before the transport closes, and the terminal `.cancelled` is recorded before the transport closes. The header of `MCPSessionSweepTests` states this.
    - The `SurfaceRefresher` of `^7vn4nk5` does not exist. The hook is the `Stoppable` protocol and `MCPServerPool.attach(_:)`; `shutdownAll()` stops the attachment first.
    - New shared test support: `WireRecordingTransport` (Support), `ProcessLiveness` (Support, and `StdioServerProcessTests` now reads it), `SessionMount` (Fixtures), and `MCPTestSupport.connectedRecordingMCPServer(to:name:)`.
    - The repository holds no `.swift-format` configuration file, thus no formatter ran.
  timestamp: 2026-08-27T21:51:17.394464+00:00
- actor: claude-code
  id: 01m12k9tshp9pmjppqdcgwwjnf
  text: |-
    ### implement — changed
    - evidence: 13 files — Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/CancellationNotices.swift (new), Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Call.swift, Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServer+Connection.swift, Sources/FoundationModelsMultitool/Invocation/InFlightInnerCalls.swift (new), Sources/FoundationModelsMultitool/MultiTool.swift, Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift (new), Tests/FoundationModelsMultitoolTests/Support/WireRecordingTransport.swift (new), Tests/FoundationModelsMultitoolTests/Support/ProcessLiveness.swift (new), Tests/FoundationModelsMultitoolTests/Support/MCPTestSupport.swift, Tests/FoundationModelsMultitoolTests/Fixtures/SessionMountFixtures.swift (new), Tests/FoundationModelsMultitoolTests/StdioServerProcessTests.swift. `swift build --build-tests` clean; `swift test`: 1282 tests in 97 suites passed, 0 warnings; `swift test --filter MCPSessionSweepTests`: 5 of 5 passed, 5 runs in a row.
    - next: /test, then /commit, then /review.
  timestamp: 2026-08-27T21:51:31.121177+00:00
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
- 01M112DXH2AS8Z8VNYAD9QXVY4
position_column: doing
position_ordinal: '80'
title: Session teardown sweep for MCP calls and server subprocesses
---
## What
eventplan.md § "Background tools and the completion token": "Session teardown does one deterministic sweep of the mailbox. ... MCP requests get the advisory cancel and post `.cancelled` before the transport closes." And § "Consolidation of the siblings": "To kill a server subprocess is a host-level act on each in-flight call that it carries. It is not a run cancellation."

Shell already has its sweep (`ShellSessionSweepTests.swift`). Give MCP the same, in two steps that keep their order.

- Step 1 — in-flight calls, two shapes:
  - Inside a parked `runCode` run: the session sweep cancels the run; Task cancellation reaches `MCPServer.call`, which sends `notifications/cancelled` and throws; the run's terminal `.cancelled` posts through the engine.
  - Mounted natively on a `RoutedSession` (a plain run-to-completion call, never parked): the sweep cancels the session's in-flight turn task; the same cancellation reaches `MCPServer.call` the same way. No run-plane entry exists; the advisory cancel still goes out before the transport closes. State this shape in the header, because eventplan.md speaks of "MCP requests" without the distinction.
  This task adds the tests that prove the order for both shapes: the advisory cancel is on the wire BEFORE the transport closes.
- Step 2 — server subprocesses. Add `MCPServerPool` in `Sources/FoundationModelsMultitool/Capabilities/MCP/MCPServerPool.swift`, recorded by `withMCP(servers:)`, with `public func shutdownAll() async`: `disconnect()` on each server and `shutdown()` on each `StdioServerProcess`, and `stop()` on the `SurfaceRefresher` if one is attached. A host calls it after the session sweep. Servers are infrastructure with session lifetime; they get no `completionToken`.
- Wire step 2 where the shell store closes at session end (see how `ShellState` is released at teardown, and follow the same route).
- The crash edge (no teardown ran) needs no code here: Router's restoration marks journaled runs with no terminal event as `.lost`.

## Acceptance Criteria
- [x] Parked shape: at session end with a `runCode` run that awaits a slow `ScriptedTool`, the server receives `notifications/cancelled` for that request, then the terminal event for the run is `.cancelled`, then the transport closes. The recorded order is asserted.
- [x] Native shape: at session end with an `MCPTool` mounted directly on a `RoutedSession` and a slow call in flight, the server receives `notifications/cancelled`, then the transport closes.
- [x] `shutdownAll()` ends each server subprocess, and `ProcessRegistry.global` no longer holds it.
- [x] A session with no MCP servers is unchanged.
- [x] `swift build` succeeds.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift` in the pattern of `ShellSessionSweepTests.swift`, with the criteria above. Use `ScriptedServer` over a recording in-memory transport for the two order cases, and `mcp-test-server` over stdio for the subprocess case.
- [x] `swift test --filter MCPSessionSweepTests` passes.

## Workflow
- Use `/tdd` — write the order tests first, then implement the pool and its shutdown. #eventplan #phase-4