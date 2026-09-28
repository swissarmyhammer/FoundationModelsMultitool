---
assignees:
- claude-code
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: todo
position_ordinal: '8580'
title: 'OTel 6: multitool-cli depends on swift-otel and bootstraps logging, tracing and metrics, with a guard that keeps logs off stdout'
---
## What
The design (2026-09-28): only executables depend on `swift-otel`, and each one calls `OTel.bootstrap` one time at startup. The standard `OTEL_*` environment variables configure it. An executable must always bootstrap logging. If `OTEL_EXPORTER_OTLP_ENDPOINT` is not set, it uses a handler that writes to stderr or does nothing, because the default swift-log handler writes to stdout. `multitool-cli` writes its answers to stdout (`CLIRunner.standardOutput`, `CLIAnswerDrain.swift`).

The executable target is `Sources/multitool-cli/main.swift`. Its implementation is the `MultitoolCLI` library (`CLIRunner.run(arguments:)`).
- [ ] `Package.swift`: add `swift-otel` and link its product to the `multitool-cli` executable target ONLY. If the bootstrap code must be in `MultitoolCLI` for tests, put it behind a small function that `main.swift` calls, and link `swift-otel` to `MultitoolCLI`. Write in the manifest why it is there. It must never be on the `FoundationModelsMultitool` library target.
- [ ] At startup, before any log or span: with `OTEL_EXPORTER_OTLP_ENDPOINT` set, call `OTel.bootstrap` for logs, traces and metrics. With no endpoint, bootstrap swift-log to a stderr handler (or a no-op handler), and leave tracing and metrics as no-op.
- [ ] At exit, flush and shut down the OTel exporters, so that the last spans and log records are sent. This includes an exit after `answerFailed` (exit code 70).

## Acceptance Criteria
- [ ] With no `OTEL_*` variable set, a `multitool-cli` run writes nothing but answers to stdout. All log output goes to stderr or nowhere.
- [ ] With `OTEL_EXPORTER_OTLP_ENDPOINT` set, the CLI bootstraps OTel one time.
- [ ] `PackageManifestTests`: only the executable target (or `MultitoolCLI`, with the reason) links swift-otel.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CLITelemetryBootstrapTests.swift` (new): the choice function gives "OTel" with an endpoint and "stderr" without one, from an injected environment dictionary.
- [ ] A test that runs the CLI entry point with a stub session, captures stdout and stderr, and asserts that a log line from the library goes to stderr and not to stdout.
- [ ] `PackageManifestTests`: the library target has no swift-otel product.
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.