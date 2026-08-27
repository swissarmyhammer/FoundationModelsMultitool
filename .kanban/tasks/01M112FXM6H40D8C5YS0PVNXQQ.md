---
assignees:
- claude-code
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
- 01M112DXH2AS8Z8VNYAD9QXVY4
position_column: todo
position_ordinal: '8e80'
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
- [ ] Parked shape: at session end with a `runCode` run that awaits a slow `ScriptedTool`, the server receives `notifications/cancelled` for that request, then the terminal event for the run is `.cancelled`, then the transport closes. The recorded order is asserted.
- [ ] Native shape: at session end with an `MCPTool` mounted directly on a `RoutedSession` and a slow call in flight, the server receives `notifications/cancelled`, then the transport closes.
- [ ] `shutdownAll()` ends each server subprocess, and `ProcessRegistry.global` no longer holds it.
- [ ] A session with no MCP servers is unchanged.
- [ ] `swift build` succeeds.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/MCPSessionSweepTests.swift` in the pattern of `ShellSessionSweepTests.swift`, with the criteria above. Use `ScriptedServer` over a recording in-memory transport for the two order cases, and `mcp-test-server` over stdio for the subprocess case.
- [ ] `swift test --filter MCPSessionSweepTests` passes.

## Workflow
- Use `/tdd` — write the order tests first, then implement the pool and its shutdown. #eventplan #phase-4