---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3pp4rjwtd2zcavd9tandsm3
  text: |-
    Research (implement step):
    - `os.Logger` calls are in `MCPServer+Connection.swift` (9), `MCPServer+Call.swift` (2), `MCPServer+Elicitation.swift` (4) and `MCPServer+LiveCatalog.swift` (2). `MCPServer.swift` has the stored `logger` and the `public static let defaultLogger`. `MCPServer+Discovery.swift` has `import os` and no log call. `MCPCapability.swift` has only a header comment about `os.Logger`. `SurfaceRefresher.swift` was done by OTel 2.
    - `isCurrentGeneration(_:orDiscard:error:)` takes a free message string. Its callers are in `MCPServer+Connection.swift`, `MCPServer+Call.swift` and `MCPServer+ClientQueue.swift`. The message must become a constant `MultitoolTelemetry.LogMessage`, thus `MCPServer+ClientQueue.swift` changes too.
    - Each old message puts `String(describing: error)`, a URL of an elicitation or a free text into the message. The new records use constant messages; an error goes in as `errorMetadata(of:)` (type and code only). The URL of an elicitation is content and is not logged.
    - `StdioServerProcess.swift` builds `StdioTransport(input:output:)` with no logger, thus the wrapper hands on a no-op logger. The fix gives `StdioTransport` the logger `MultitoolTelemetry.logger`, and the wrapper hands it on.
    - No MCP test support uses `os.Logger`. `FlakyConnectTransport` uses a no-op swift-log logger and needs no change.
    - Tests: `MCPServer` takes `logger: context.logger` of a `TelemetryCapture`, because the actor logs from its own tasks.
  timestamp: 2026-09-29T13:37:23.036028+00:00
- actor: claude-code
  id: 01m3pphgfjr10cg254raz8mk1v
  text: |-
    ### implement — changed
    - evidence: files changed — `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift` (20 new `LogMessage` cases for MCP, 4 new `LogMetadataKey` cases: `connectAttempt`, `connectAttemptLimit`, `peerServerName`, `elicitationID`), `Diagnostics/MultitoolTelemetry+Logging.swift` (`durationMetadata(of:)`, `serverNameMetadata(_:)`), `Capabilities/MCP/MCPServer.swift` (`defaultLogger` is now a computed swift-log logger; new `record(_:level:metadata:)` adds the server name), `MCPServer+Connection.swift`, `MCPServer+Call.swift`, `MCPServer+ClientQueue.swift` (`isCurrentGeneration(_:orDiscard:error:)` now takes a `LogMessage`), `MCPServer+Elicitation.swift`, `MCPServer+LiveCatalog.swift`, `MCPServer+Discovery.swift` (removed `import os`), `MCPCapability.swift` (header comment), `StdioServerProcess.swift` (`StdioTransport` gets `MultitoolTelemetry.logger`; comments updated). Tests: new `Tests/FoundationModelsMultitoolTests/MCPLogRecordTests.swift` (failed connect, reconnect, transport drop under a tool call; each forbids the error text or the tool argument), new case in `StdioServerProcessTests.swift` (the vended transport logger has `MultitoolTelemetry.logLabel`).
    - evidence: red first — `swift build --build-tests` failed on the missing vocabulary cases and on `os.Logger` in `MCPServer.init`. Then `swift build --build-tests`: 0 errors, 0 code warnings. `rg -n 'os\.Logger|Logger\(subsystem' Sources/FoundationModelsMultitool/Capabilities/MCP`: no match.
    - evidence: `swift test --filter 'MCPLogRecordTests|StdioServerProcessTests|ResilienceTests|LostCallTests|MultitoolTelemetryTests|MCPServerCallTests|LiveCatalogTests|CoreLogRecordTests|SurfaceRefresherTests|Elicitation|TransportFactoryTests|MCPServerDiscoveryTests|DropObservingTransportTests'`: 106 tests in 14 suites passed, 0 failed.
    - warning: the one full `swift test` run of this step gave no result. I piped its output into `head`, and `head` stopped the run early. The user rule permits one run of each test command, so I did not run it again. The full suite is NOT verified.
    - design notes: no MCP payload goes into a record. An error goes in as type and code only (`errorMetadata(of:)`). The URL of a URL-mode elicitation is content, thus the record holds the elicitation id and not the url. A tool-call error has no log call of its own in `MCPServer+Call.swift`; the test covers the transport-drop record, which is the record of a failed call in flight.
    - next: the `/test` step must run the full `swift build --build-tests && swift test` one time and check the last unchecked boxes. Then `/review`.
  timestamp: 2026-09-29T13:44:20.722553+00:00
- actor: claude-code
  id: 01m3ppp5e3jyggva624dp0yt1p
  text: |-
    ### test — green
    - evidence: The 16 changed Swift files were touched. `swift build --build-tests` completed with exit 0 and 0 compiler warnings from this package. `swift test` ran one time: Swift Testing ran 1840 tests in 149 suites; all passed, 0 failed, 0 skipped. XCTest ran 0 tests with 0 failures. `swift build --package-path IntegrationTests --build-tests` completed with exit 0 and 0 compiler warnings or errors. The only other messages were the known SwiftPM "cached manifest ... disk I/O error" and "missing creator for mutated node ... mlx-swift_Cmlx.bundle" messages. These are not warnings of this package.
    - next: Do the review step.
  timestamp: 2026-09-29T13:46:53.251741+00:00
- actor: claude-code
  id: 01m3ppy1wthfz5z70mwsmvnndr
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 88aa828). 0 findings (confirmed 0, refuted 0). 13 files reviewed. 4 files in .kanban/ not reviewed (.reviewignore). No prior findings sections.
    - next: The task moved to done.
  timestamp: 2026-09-29T13:51:11.770243+00:00
- actor: claude-code
  id: 01m3ppydvsrsmvrfvhan4nhma7
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 14 files (MCP files to the shared swift-log logger; new MCPLogRecordTests.swift)
    - test: green — swift build --build-tests, 0 package warnings; swift test 1840 tests in 149 suites passed (one run); IntegrationTests build passed
    - commit: 88aa828
    - review: clean — 0 findings
  timestamp: 2026-09-29T13:51:24.025453+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: done
position_ordinal: fffd80
title: 'OTel 3: replace os.Logger with swift-log in the MCP capability files'
---
## What
The design (2026-09-28): remove all `os.Logger` use and use `Logging.Logger` (swift-log). No MCP payload, tool argument or tool output goes into a log message or log metadata. Server names, method names, request ids, counts and sizes are safe. Use the label and keys from `MultitoolTelemetry` (task OTel 1).
- [x] Change `os.Logger` to `Logging.Logger` in `Sources/FoundationModelsMultitool/Capabilities/MCP/`: `MCPCapability.swift`, `MCPServer.swift` (2 uses), `MCPServer+Call.swift`, `MCPServer+Connection.swift`, `MCPServer+Discovery.swift`, `MCPServer+Elicitation.swift`, `MCPServer+LiveCatalog.swift` and `SurfaceRefresher.swift`. Remove `import os` where nothing else needs it.
- [x] `StdioServerProcess.swift` wraps the MCP sdk `Transport`, which requires a `Logging.Logger` property. Give it a real logger with the Multitool label, in place of the current placeholder that logs nothing. Update its comment at `:59`.
- [x] Change the MCP test support that uses `os.Logger`, if any, to the in-memory swift-log handler of OTel 2. If OTel 2 is not done yet, add the handler here in `Tests/Support/MultitoolTestSupport/` and let OTel 2 reuse it.

## Acceptance Criteria
- [x] `rg -n 'os\.Logger|Logger\(subsystem' Sources/FoundationModelsMultitool/Capabilities/MCP` returns no match.
- [x] Each changed log call keeps its level and its event.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/` (MCP suites that use `ScriptedServer`): for a failed connect, a reconnect and a tool-call error, the expected swift-log record occurs with the server name in metadata, and it has no request or result payload text.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.