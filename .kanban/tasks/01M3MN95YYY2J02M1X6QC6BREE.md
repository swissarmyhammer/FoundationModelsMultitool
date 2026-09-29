---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnc75nt2850bx1565eyry4
  text: 'Related Extras task (from the swissarmyhammer session, 2026-09-28): Extras OTel A ^65xmgkv (01M3MN838VZ4QX57C3965XMGKV) adds swift-log and swift-metrics to the Extras core target as API only. This task does not wait for it: declare the two products here directly. If Extras OTel A is already on origin/main when this task starts, check that the two packages resolve to one version.'
  timestamp: 2026-09-28T18:45:29.909484+00:00
- actor: claude-code
  id: 01m3phbkpqwxjk1myt0rj7pkpr
  text: |-
    Research (implement step):
    - Extras on local main is at 6c399a4. Its core target links `Tracing` (swift-distributed-tracing 1.4.1+), `Logging` (swift-log 1.15.1+) and `Metrics` (swift-metrics 2.11.0+). `ExtrasTelemetry.swift` names the span `FoundationModelsExtras.tool`, the attribute keys `tool.name`, `session.id`, `tool.run_kind`, `tool.outcome`, and the metrics `FoundationModelsExtras.tool.calls` and `FoundationModelsExtras.tool.duration`.
    - `Package.resolved` of this package already pins swift-log 1.15.1, swift-metrics 2.11.0 and swift-distributed-tracing 1.5.0 (through Extras). Thus the direct declarations here resolve to the same one version. Use the same floors as Extras.
    - The model vocabulary is `../FoundationModelsRouter/Sources/FoundationModelsRouter/Tracing/RouterTelemetry.swift` (the file name changed from `RouterTracing.swift`).
    - `CallTrace` span names today: `MultiTool.call`, `SearchToolsTool.call` (with `.search`, `.generateSample`, `.makeSampleSession`, `.makeSelectionSession`), `RunBinding.invoke`, `AgentSession.respond`, `AgentSession.fork`.
    - `DropObservingTransport.swift:31` also says that it "logs nothing" through `Logging.Logger`. That is not the manifest statement, thus this task does not change it. OTel 3 owns the MCP logging.
    - Decision: the vocabulary uses `String` raw-value `CaseIterable` enums. The compiler rejects two equal raw values in one enum, and the tests read `allCases`, thus no name can be left out of a test list.
  timestamp: 2026-09-29T12:13:44.535195+00:00
- actor: claude-code
  id: 01m3phssb5c5dx50yxf38yp4vp
  text: |-
    ### implement — changed
    - evidence: 6 files. `Package.swift` (new `loggingPackage`, `metricsPackage` and `telemetryProducts` with floors 1.15.1 and 2.11.0, the same floors as Extras; the library target links `telemetryProducts`; the "declares no swift-log" comments are gone), `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift` (new), `Sources/FoundationModelsMultitool/Capabilities/MCP/StdioServerProcess.swift` and `MCPCapability.swift` (comments only), `Tests/FoundationModelsMultitoolTests/MultitoolTelemetryTests.swift` (new, 4 tests), `Tests/FoundationModelsMultitoolTests/PackageManifestTests.swift` (2 new tests). TDD: the tests failed first (the build failed with "cannot find 'MultitoolTelemetry' in scope"). `swift build --build-tests` exit 0. `swift test --filter "PackageManifestTests|MultitoolTelemetryTests"`: 9 tests in 2 suites passed. `swift test`: 1828 tests in 147 suites passed, 0 failed. `Package.resolved` did not change (swift-log 1.15.1 and swift-metrics 2.11.0 already resolved through Extras, thus one version each).
    - notes: The vocabulary uses `String` raw-value `CaseIterable` enums (`SpanName`, `AttributeKey`, `MetricName` with `dimensionKeys`, `LogMetadataKey`) and one `logLabel` (`FoundationModelsMultitool.log`). Each metric dimension key is an `AttributeKey`, and each `LogMetadataKey` names a fact that no attribute key names, thus no two names are the same across the whole file. The file has `// periphery:ignore:all` with a reason line, because OTel 2 to OTel 7 are its readers. The library target links `Metrics`, but no source file imports it yet. OTel 7 is the first reader. The build and test logs show SwiftPM "failed loading cached manifest ... disk I/O error" warnings and one "missing creator for mutated node" warning on the `mlx-swift_Cmlx.bundle`. These come from the SwiftPM cache and the MLX bundle of the environment, not from this change.
    - next: review (the task stays in `doing`).
  timestamp: 2026-09-29T12:21:29.061743+00:00
- actor: claude-code
  id: 01m3pj348h0yxnx2bfgy08ysaa
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` completed with exit 0. Before the second build, the mtime of the 5 changed Swift files was updated (no content change) to force a new compile. That build showed 0 compiler warnings and 0 errors. `swift test` completed with exit 0: 1828 tests in 147 suites passed, 0 failed, 0 skipped. XCTest ran 0 tests. `swift build --package-path IntegrationTests --build-tests` completed with exit 0 and 0 compiler warnings. The live-model suite was not run. The only other messages are SwiftPM "cached manifest ... disk I/O error" and "missing creator for mutated node ... mlx-swift_Cmlx.bundle". These do not come from this package.
    - next: review
  timestamp: 2026-09-29T12:26:35.153524+00:00
- actor: claude-code
  id: 01m3pjfpm5gg7m5ywqjjanzxff
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 629ece7). counts: findings 0, confirmed 0, refuted 1, attempted 7, failed 0, skipped 0. 6 files reviewed. 2 files in .kanban/ are not reviewed (.reviewignore). The task has no prior Review Findings sections.
    - next: The task is in done. None.
  timestamp: 2026-09-29T12:33:27.173755+00:00
- actor: claude-code
  id: 01m3pjg7tx30psee89c1699s3g
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files (Package.swift, MultitoolTelemetry.swift, StdioServerProcess.swift, MCPCapability.swift, MultitoolTelemetryTests.swift, PackageManifestTests.swift)
    - test: green — swift test 1828 tests in 147 suites passed; IntegrationTests build passed
    - commit: 629ece7
    - review: clean — 0 findings
  timestamp: 2026-09-29T12:33:44.797607+00:00
position_column: done
position_ordinal: fffb80
title: 'OTel 1: add the Multitool telemetry vocabulary file, and declare swift-log and swift-metrics as API-only dependencies'
---
## What
Design approved by the user on 2026-09-28 (OpenTelemetry for the FoundationModels packages, from the swissarmyhammer session): libraries use only the APIs `swift-distributed-tracing` (`Tracing`), `swift-log` (`Logging`) and `swift-metrics` (`Metrics`). Only executables depend on `swift-otel`. Each package has ONE vocabulary file that holds its span names, attribute keys, metric names and log metadata keys, and each name starts with the module name as a prefix. The model is `../FoundationModelsRouter/Sources/FoundationModelsRouter/Tracing/RouterTracing.swift`, which uses the prefix `FoundationModelsRouter.`.

- [ ] `Package.swift`: declare `swift-log` (`Logging`) and `swift-metrics` (`Metrics`) and link them to the library target `FoundationModelsMultitool`. `Tracing` comes through FoundationModelsExtras (Extras commit ffa4058 added swift-distributed-tracing). If the library needs the product directly, declare it. Remove the manifest comments that say this package does not declare `swift-log` on purpose (`Package.swift:243-263`, `:574-577`), and the same statement in `Capabilities/MCP/StdioServerProcess.swift:59` and `Capabilities/MCP/MCPCapability.swift:58`. Do NOT add `swift-otel` to any library target.
- [ ] Add `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift` (an `enum`). It holds:
  - span names for the four current `CallTrace` points (`MultiTool.call`, `SearchToolsTool.call`, the `RunBinding.invoke` `tools.*` dispatch, `TracedAgentSession`) and for the MCP client call
  - attribute keys (tool name, verb, op, noun, server name, outcome, sizes and counts only)
  - metric names and dimension keys for the tool-call count and duration, the MCP server errors and restarts, and the JS interpreter run duration
  - the log label and the log metadata keys
  
  Prefix each name with the module name, `FoundationModelsMultitool.`. Its doc comment states the no-content rule: no prompt or response text, tool arguments, tool output, JS source, embed input text or MCP payloads in a span attribute, log message, log metadata value or metric dimension. Identifiers, names, counts and sizes are safe.
- [ ] This task only adds the file and the dependencies. The tasks OTel 2 to OTel 7 use them.

## Acceptance Criteria
- [ ] `swift build --build-tests` and `swift test` pass.
- [ ] The library target links `Logging` and `Metrics`, and no library target links `OTel` / `swift-otel`.
- [ ] Each name in `MultitoolTelemetry` starts with `FoundationModelsMultitool.`, and no two names are the same.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/PackageManifestTests.swift`: the library target lists the swift-log and swift-metrics products and no swift-otel product.
- [ ] `Tests/FoundationModelsMultitoolTests/MultitoolTelemetryTests.swift` (new): each span, attribute, metric and log key starts with `FoundationModelsMultitool.`, and the names are unique.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.