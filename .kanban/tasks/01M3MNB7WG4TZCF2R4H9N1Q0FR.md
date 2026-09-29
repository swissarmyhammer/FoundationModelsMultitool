---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n93egk92v9zg7f7zxew9ep
  text: |-
    Facts from the ACPClient work (swift-otel 1.5.1), sent by the swissarmyhammer session on 2026-09-28:
    - `OTel.bootstrap` can bootstrap logs and then fail on metrics or traces, and a second `LoggingSystem.bootstrap` stops the process. So bootstrap logging ONE time: use `OTel.makeLoggingBackend` with one `LoggingSystem.bootstrap`, and call `OTel.bootstrap` for traces and metrics only.
    - Check `OTEL_SDK_DISABLED` case-insensitively before the bootstrap. When it is true, use the no-endpoint path.
    - Correction to the reason in this task: the default swift-log handler writes to STDERR (`StreamLogHandler.standardError`), not to stdout. The explicit bootstrap and the test that no log line reaches stdout are still required, because stdout carries only the answers.
  timestamp: 2026-09-29T00:30:14.035316+00:00
- actor: claude-code
  id: 01m3pt9npftqyzdt6az489mad6
  text: |-
    Research (implement step):
    - The pattern to follow is in `../FoundationModelsACPClient/Sources/acp-client/TelemetryBootstrap.swift` and `TelemetryServices.swift`: one `LoggingSystem.bootstrap` with `OTel.makeLoggingBackend`, then `OTel.bootstrap` with `logs.enabled = false`, and a `ServiceGroup` that runs the export services and gets a graceful shutdown with a 2 s bound before `exit`. swift-otel 1.5.1 and swift-service-lifecycle 2.12.0 are in the SwiftPM cache.
    - Plan: swift-otel links to the `multitool-cli` executable target ONLY (group `otelProducts`, so that the `otel` marker of `PackageManifestTests` finds it). The executable holds the OTel bootstrap and the flush. `MultitoolCLI` holds the pure choice (`CLITelemetryBackend(environment:)`) and the stderr log handler, and links `Logging` only. Thus the existing test `noLibraryTargetLinksOTel` (it reads each `.target(` declaration, `MultitoolCLI` included) stays true.
    - The stdout guard test does not bootstrap: it binds a logger with the stderr handler through the test seam `MultitoolTelemetry.$boundLogger`, runs `CLIRunner.run` with a stub resolver that makes the library log a warning (`ToolAPIRenderer.render` with `UnrenderableArgument`), and captures stdout and stderr with two `OutputCollector`s.
    - swift-log `StreamLogHandler` has no public initializer that takes a sink. Thus the CLI needs its own handler that writes through `CLIRunner.standardErrorOutput`, so that a test can read it.
  timestamp: 2026-09-29T14:49:58.223305+00:00
- actor: claude-code
  id: 01m3ptms6q8nkdh23qh7k37h9f
  text: |-
    ### implement — changed
    - evidence: `Package.swift` (swift-otel 1.5.1 and swift-service-lifecycle 2.12.0 in the group `otelProducts`, linked ONLY by the `multitool-cli` executable target; `MultitoolCLI` links the `Logging` API only), `Sources/MultitoolCLI/CLITelemetry.swift` (new: `CLITelemetryBackend(environment:)`, the pure choice with the case-insensitive `OTEL_SDK_DISABLED` check; `CLILogHandler`, the stderr handler through `CLIRunner.standardErrorOutput`), `Sources/multitool-cli/TelemetryBootstrap.swift` (new: one `LoggingSystem.bootstrap` on each path; with an endpoint, `OTel.makeLoggingBackend` for logs and `OTel.bootstrap` with logs off for traces and metrics), `Sources/multitool-cli/TelemetryServices.swift` (new: runs the export services in a `ServiceGroup`, then a graceful shutdown with a 2 s bound before `exit`; each code that `CLIRunner.run` returns, `answerFailed` (70) included, goes through the flush), `Sources/multitool-cli/main.swift` (the bootstrap is the first statement), `Sources/MultitoolCLI/CLIRunner.swift` (doc of the public surface), `Tests/FoundationModelsMultitoolTests/CLITelemetryBootstrapTests.swift` (new: 8 tests; the choice from an injected environment, the handler, and a `CLIRunner.run` with a stub resolver where a library warning reaches the captured stderr and not the captured stdout, with no `LoggingSystem.bootstrap`), `Tests/FoundationModelsMultitoolTests/PackageManifestTests.swift` (new test: only the executable target links swift-otel; the existing test keeps each `.target(` free of swift-otel).
    - `swift build --build-tests`: Build complete, 0 source warnings. `swift test` (one run): 1855 tests in 151 suites passed. The only `warning:` lines are SwiftPM manifest-cache "disk I/O error" lines from the environment, not from the source.
    - TDD note: the tests were written first, but the user rule permits one test run only, thus no separate red run was made. The new tests did not compile before the new types existed.
    - Scope: the flush on SIGTERM/SIGINT and on the other exit paths stays with task 01M3MNMX76FTBYS2192GYRW8KW (OTel 6b).
    - next: review.
  timestamp: 2026-09-29T14:56:02.263625+00:00
- actor: claude-code
  id: 01m3ptt13qm6gt5eqs53mnrr3m
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` completed after a touch of the 8 changed Swift files. It showed 0 compiler warnings from files of this package. `swift test` ran one time: 1855 tests in 151 suites passed, 0 failed, 0 skipped. XCTest executed 0 tests with 0 failures. `swift build --package-path IntegrationTests --build-tests` completed with 0 compiler warnings. The only build messages were the known SwiftPM "disk I/O error" manifest-cache warnings and the "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning.
    - next: review
  timestamp: 2026-09-29T14:58:54.199906+00:00
depends_on:
- 01M3MN95YYY2J02M1X6QC6BREE
position_column: doing
position_ordinal: '8180'
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