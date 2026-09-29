---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n93hf9j0arb979dqtf5p8z
  text: 'Fact from the ACPClient work (swift-otel 1.5.1), sent by the swissarmyhammer session on 2026-09-28: a graceful-shutdown timeout of swift-service-lifecycle ends in `fatalError`. Do not use it for the bounded flush. Use a bound of your own (ACPClient uses 2 seconds), for example a task group that races the flush against a sleep.'
  timestamp: 2026-09-29T00:30:17.065368+00:00
- actor: claude-code
  id: 01m3pyrc69whm1jdhga5cz3hvc
  text: |-
    Implement notes (research and discoveries):
    - The one exit path is `CLIExitPath` in `Sources/MultitoolCLI/CLIExitPath.swift`. It opens the run span `multitool-cli.run` (attribute `process.exit.code`, error status on a code that is not 0), runs the command in a task, and races it against the stop signals. On each end it ends the span, then flushes with its own 2-second bound (a race of two tasks, not the swift-service-lifecycle timeout, which ends in `fatalError`). A thrown error gives one line on standard error and exit code 69. `main.swift` has the only `exit`, after the flush. `TelemetryServices.runThenExit` and its two `exit` calls are gone; `TelemetryServices.start()` now gives the flush closure, or `nil` with no exporter (then the path does not wait).
    - Signals: `CLIStopSignal.makeSignalStream()` puts a no-op C handler and a `DispatchSource` on SIGINT and SIGTERM. Not `SIG_IGN`: an ignored signal stays ignored in each child after `exec`, and `StdioServerProcess` uses raw `posix_spawn` with no `SETSIGDEF`. On a signal the path runs `CLIRunCancellation.cancel()` (the run adds `session.cancel()` when it makes the session), cancels the command task, waits 2 s at most, and gives 128 + signal.
    - The run span ends also when the command does not end in the bound. A measured case: a `--mcp` connect to a server that never answers `initialize` does not stop on task cancellation; the path waits the full 2 s bound and still exports the span.
    - Stub run for the child-process test: new `ServerMode.stall` of `mcp-test-server` (reads stdin to its end, answers nothing). The CLI stays open in the MCP connect, before any model resolution. No test switch in production code.
    - LATENT BUG OF OTel 6, fixed here: with `OTEL_SDK_DISABLED=false` set, `OTel.bootstrap` turns the logs on again (`logs.disabled.override(using: .sdkDisabled)`), bootstraps logging a second time, and the process stops with SIGTRAP at start. `TelemetryBootstrap.bootstrapTracingAndMetrics` now gives `OTel.bootstrap` the environment without that variable. `CLITelemetryBackend.sdkDisabledVariable` is `public` for this.
    - `NWListener` fails with EINVAL when it starts before `newConnectionHandler` is set. The first test run hit this in `OTLPTestCollector`; the handler is now set before the start.
    - In this sandbox a Python HTTP server on loopback gets no connections, but `NWListener` works.
    - Test partitioning note for review: `CLISignalExitTests` is in the unit target and starts child processes and a loopback socket. This follows the precedent of `CLIArgumentTests` and `StdioServerProcessTests`, which start `mcp-test-server` in the same target.
  timestamp: 2026-09-29T16:07:54.313911+00:00
- actor: claude-code
  id: 01m3pyrmdx64twm6gsq5hm803k
  text: |-
    ### implement — changed
    - evidence: 12 files. New: Sources/MultitoolCLI/CLIExitPath.swift, Tests/FoundationModelsMultitoolTests/CLITelemetryShutdownTests.swift, Tests/FoundationModelsMultitoolTests/CLISignalExitTests.swift, Tests/FoundationModelsMultitoolTests/Support/OTLPTestCollector.swift. Changed: Sources/MultitoolCLI/CLIRunner.swift, Sources/MultitoolCLI/CLITelemetry.swift, Sources/multitool-cli/main.swift, Sources/multitool-cli/TelemetryServices.swift, Sources/multitool-cli/TelemetryBootstrap.swift, Tests/Support/MCPTestServer/ServerMode.swift, Tests/Support/mcp-test-server/main.swift, Tests/FoundationModelsMultitoolTests/ServerModeTests.swift. Red first: `swift build --build-tests` failed on the missing `CLIExitPath` and `CLIStopSignal`. The one `swift test` run: 1873 tests in 155 suites, 2 issues, both in `CLISignalExit` (`listenerFailed(EINVAL)`: the collector set its connection handler after `NWListener.start`). `CLITelemetryShutdown`, `ServerMode` and `CLITelemetryBootstrap` passed. After that run: the collector order is fixed, and the OTel 6 bug with `OTEL_SDK_DISABLED=false` is fixed. `swift build --build-tests` exits 0. A standalone harness (swiftc with the same `OTLPTestCollector.swift`, not `swift test`) does the steps of `CLISignalExitTests` on the built binary: SIGTERM gives exit 143 and SIGINT gives exit 130, `terminationReason == .exit`, and each run sends 1 `/v1/traces` request that holds `multitool-cli.run`. `swift test` did not run again, because the user allows one test run.
    - next: the test step runs `swift build --build-tests && swift test` and confirms `CLISignalExit` is green. Then review.
  timestamp: 2026-09-29T16:08:02.749341+00:00
- actor: claude-code
  id: 01m3pywm987c7a00t2njg398fc
  text: |-
    ### test — green
    - evidence: I touched the 12 changed Swift files from `git status`. `swift build --build-tests` completed with exit 0. It showed 0 compiler warnings and 0 errors from files of this package. `swift test` ran one time to the end with exit 0: "Test run with 1873 tests in 155 suites passed". It had 0 failures and 0 skipped tests. XCTest executed 0 tests. The suite "CLISignalExit" passed after 2.721 seconds. `swift build --package-path IntegrationTests --build-tests` completed with exit 0 and 0 compiler warnings. The only build messages were SwiftPM "failed loading/storing cached manifest ... disk I/O error" and "missing creator for mutated node ... mlx-swift_Cmlx.bundle". These messages do not come from this package.
    - next: review
  timestamp: 2026-09-29T16:10:13.672463+00:00
depends_on:
- 01M3MNB7WG4TZCF2R4H9N1Q0FR
position_column: doing
position_ordinal: '8180'
title: 'OTel 6b: multitool-cli shuts down OTel on every exit path, including SIGTERM and SIGINT, so the last span is exported'
---
## What
The ACPClient session found (2026-09-28) that an OTLP batch exporter does not send its last data if the process calls `exit()` or ends on a signal. OTel 6 (01M3MNB7WG4TZCF2R4H9N1Q0FR) bootstraps OTel and flushes it at a normal end and after `answerFailed`. This task covers EVERY exit path of `multitool-cli` (`Sources/multitool-cli/main.swift`, `Sources/MultitoolCLI/CLIRunner.swift`):
- [ ] List each exit path: the normal end, each `CLIRunner.ExitCode` error path (argument errors, model resolution errors, `answerFailed` = 70, the mail-wait time limit), a thrown error that reaches `main`, and each direct `exit(...)` call. Make each one go through one shutdown function that flushes and shuts down the trace, log and metric exporters, and then returns the exit code. Remove the direct `exit(...)` calls, or make them call the shutdown function first.
- [ ] Handle SIGTERM and SIGINT with a `DispatchSource` signal source (or the swift-service-lifecycle graceful shutdown, if swift-otel already brings it). On a signal: cancel the running session (`cancel()`), run the shutdown function with a bounded time (for example 5 s), and then exit with the conventional code (128 + signal number).
- [ ] With no OTLP endpoint (the stderr or no-op path of OTel 6), the shutdown function does nothing and costs nothing.

## Acceptance Criteria
- [ ] The last span of a run is exported on each path: normal end, error exit, SIGINT and SIGTERM.
- [ ] A signal during a running answer ends the process within the bounded time, and with code 128 + signal number.
- [ ] `swift build --build-tests` and `swift test` pass.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/CLITelemetryShutdownTests.swift` (new): with an in-memory or local exporter, a run through the CLI entry point with a stub session exports its last span on the normal path and on an error path.
- [ ] A test that starts the built `multitool-cli` as a child process with `OTEL_EXPORTER_OTLP_ENDPOINT` pointed at a local test collector (a loopback HTTP server that records OTLP requests; `LoopbackHTTPServer` in `Tests/Support/MCPTestServer` may help), sends SIGTERM while a stub run is open, and asserts that the collector received the run's spans and that the exit code is 143. The same for SIGINT (130).
- [ ] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.