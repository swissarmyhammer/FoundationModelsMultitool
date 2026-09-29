---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n93hf9j0arb979dqtf5p8z
  text: 'Fact from the ACPClient work (swift-otel 1.5.1), sent by the swissarmyhammer session on 2026-09-28: a graceful-shutdown timeout of swift-service-lifecycle ends in `fatalError`. Do not use it for the bounded flush. Use a bound of your own (ACPClient uses 2 seconds), for example a task group that races the flush against a sleep.'
  timestamp: 2026-09-29T00:30:17.065368+00:00
depends_on:
- 01M3MNB7WG4TZCF2R4H9N1Q0FR
position_column: todo
position_ordinal: '8880'
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