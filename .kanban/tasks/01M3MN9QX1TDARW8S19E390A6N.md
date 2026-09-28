---
assignees:
- claude-code
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: todo
position_ordinal: '8180'
title: 'OTel 2: replace os.Logger with swift-log in the core library files and their tests'
---
## What
The design (2026-09-28): remove all `os.Logger` use and use `Logging.Logger` (swift-log). The user does not want unified-logging output. Log messages and metadata must carry no content (no tool arguments, tool output, JS source or MCP payloads). Use the label and metadata keys from `MultitoolTelemetry` (task OTel 1).

This task covers the core library files. The MCP files are task OTel 3, and `CallTrace` is task OTel 4.
- [ ] Change `os.Logger` to `Logging.Logger` in `Sources/FoundationModelsMultitool/MultiTool.swift`, `MultiTool+Background.swift`, `Interpreter/JSCInterpreter.swift`, `Surface/ToolAPIRenderer.swift`, `Invocation/LostRunRecord.swift`, `Invocation/SandboxNoticeOutbox.swift` and `Invocation/ToolReturnLedger.swift`. Remove `import os` where nothing else needs it. Keep each log level and each event. Move any interpolated content out of the message. Put only names, ids, counts and sizes into metadata.
- [ ] `Tests/FoundationModelsMultitoolTests/Fixtures/LogReadbackFixtures.swift` reads the unified log back through `OSLogStore`. Replace it with a swift-log test handler that records log entries in memory, for example a `LogHandler` over a lock-protected array. It must be installed per test and not only process-wide through `LoggingSystem.bootstrap`, which can run only one time. If swift-log offers no per-logger injection, give the logging types a `Logger` parameter or a factory seam. Change the tests that use the fixture to read the in-memory records.
- [ ] Change the other test fixtures that use `os.Logger` (`AgentSessionFixtures`, `EmbeddingFixtures`, `MailProbeFixtures`, `MultiToolExecutionFixtures`, `RunBindingFixtures`, `SuspendedContextFixtures`, `ToolInvokerFixtures`, `JSCInterpreterTests`, `MultiToolExecutionTests`, `OverBudgetSelectionOrderTests`, `SampleSnippetTests`, `SearchToolsToolTests`, `Tests/Support/MultitoolTestSupport/OutputCollector.swift`), unless they belong to the MCP files of OTel 3.

## Acceptance Criteria
- [ ] `rg -n 'os\.Logger|Logger\(subsystem|OSLogStore' Sources/FoundationModelsMultitool Tests --glob '!**/Capabilities/MCP/**' --glob '!**/Diagnostics/CallTrace.swift'` returns no match.
- [ ] Each changed log call keeps its level and its event, and a test proves it for at least one call in each changed file.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] The tests that used `LogReadbackFixtures` now assert on the in-memory swift-log records, and they pass.
- [ ] A test for each changed source file: the expected log record occurs with its metadata keys, and its message has no content of the fixture (for example the JS source or the tool argument).
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.