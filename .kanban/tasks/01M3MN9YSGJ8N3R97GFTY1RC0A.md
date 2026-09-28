---
assignees:
- claude-code
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: todo
position_ordinal: '8280'
title: 'OTel 3: replace os.Logger with swift-log in the MCP capability files'
---
## What
The design (2026-09-28): remove all `os.Logger` use and use `Logging.Logger` (swift-log). No MCP payload, tool argument or tool output goes into a log message or log metadata. Server names, method names, request ids, counts and sizes are safe. Use the label and keys from `MultitoolTelemetry` (task OTel 1).
- [ ] Change `os.Logger` to `Logging.Logger` in `Sources/FoundationModelsMultitool/Capabilities/MCP/`: `MCPCapability.swift`, `MCPServer.swift` (2 uses), `MCPServer+Call.swift`, `MCPServer+Connection.swift`, `MCPServer+Discovery.swift`, `MCPServer+Elicitation.swift`, `MCPServer+LiveCatalog.swift` and `SurfaceRefresher.swift`. Remove `import os` where nothing else needs it.
- [ ] `StdioServerProcess.swift` wraps the MCP sdk `Transport`, which requires a `Logging.Logger` property. Give it a real logger with the Multitool label, in place of the current placeholder that logs nothing. Update its comment at `:59`.
- [ ] Change the MCP test support that uses `os.Logger`, if any, to the in-memory swift-log handler of OTel 2. If OTel 2 is not done yet, add the handler here in `Tests/Support/MultitoolTestSupport/` and let OTel 2 reuse it.

## Acceptance Criteria
- [ ] `rg -n 'os\.Logger|Logger\(subsystem' Sources/FoundationModelsMultitool/Capabilities/MCP` returns no match.
- [ ] Each changed log call keeps its level and its event.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/` (MCP suites that use `ScriptedServer`): for a failed connect, a reconnect and a tool-call error, the expected swift-log record occurs with the server name in metadata, and it has no request or result payload text.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.