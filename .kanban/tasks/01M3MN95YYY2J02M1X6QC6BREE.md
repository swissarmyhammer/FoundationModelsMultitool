---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mnc75nt2850bx1565eyry4
  text: 'Related Extras task (from the swissarmyhammer session, 2026-09-28): Extras OTel A ^65xmgkv (01M3MN838VZ4QX57C3965XMGKV) adds swift-log and swift-metrics to the Extras core target as API only. This task does not wait for it: declare the two products here directly. If Extras OTel A is already on origin/main when this task starts, check that the two packages resolve to one version.'
  timestamp: 2026-09-28T18:45:29.909484+00:00
position_column: todo
position_ordinal: '80'
title: 'OTel 1: add the Multitool telemetry vocabulary file, and declare swift-log and swift-metrics as API-only dependencies'
---
## What
Design approved by the user on 2026-09-28 (OpenTelemetry for the FoundationModels packages, from the swissarmyhammer session): libraries use only the APIs `swift-distributed-tracing` (`Tracing`), `swift-log` (`Logging`) and `swift-metrics` (`Metrics`). Only executables depend on `swift-otel`. Each package has ONE vocabulary file that holds its span names, attribute keys, metric names and log metadata keys, and each name starts with the module name. The model is `../FoundationModelsRouter/Sources/FoundationModelsRouter/Tracing/RouterTracing.swift`.

- [ ] `Package.swift`: declare `swift-log` (`Logging`) and `swift-metrics` (`Metrics`) and link them to the library target `FoundationModelsMultitool`. `Tracing` comes through FoundationModelsExtras (Extras commit ffa4058 added swift-distributed-tracing). If the library needs the product directly, declare it. Remove the manifest comments that say this package does not declare `swift-log` on purpose (`Package.swift:243-263`, `:574-577`), and the same statement in `Capabilities/MCP/StdioServerProcess.swift:59` and `Capabilities/MCP/MCPCapability.swift:58`. Do NOT add `swift-otel` to any library target.
- [ ] Add `Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift` (an `enum`). It holds:
  - span names for the four current `CallTrace` points (`MultiTool.call`, `SearchToolsTool.call`, the `RunBinding.invoke` `tools.*` dispatch, `TracedAgentSession`) and for the MCP client call
  - attribute keys (tool name, verb, op, noun, server name, outcome, sizes and counts only)
  - metric names and dimension keys for the tool-call count and duration, the MCP server errors and restarts, and the JS interpreter run duration
  - the log label and the log metadata keys
  
  Prefix each name with `multitool.`. Its doc comment states the no-content rule: no prompt or response text, tool arguments, tool output, JS source, embed input text or MCP payloads in a span attribute, log message, log metadata value or metric dimension. Identifiers, names, counts and sizes are safe.
- [ ] This task only adds the file and the dependencies. The tasks OTel 2 to OTel 7 use them.

## Acceptance Criteria
- [ ] `swift build --build-tests` and `swift test` pass.
- [ ] The library target links `Logging` and `Metrics`, and no library target links `OTel` / `swift-otel`.
- [ ] Each name in `MultitoolTelemetry` starts with `multitool.`, and no two names are the same.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/PackageManifestTests.swift`: the library target lists the swift-log and swift-metrics products and no swift-otel product.
- [ ] `Tests/FoundationModelsMultitoolTests/MultitoolTelemetryTests.swift` (new): each span, attribute, metric and log key starts with `multitool.`, and the names are unique.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.