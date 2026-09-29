// multitool-cli
//
// A runnable demonstration of the whole FoundationModelsMultitool pipeline:
// Router profile resolution -> a RoutedSession over the resolved .standard
// slot, carrying multiTool and (unless --direct) searchToolsTool ->
// one demo prompt, driven by draining the session's event stream.
// All the actual logic lives in the `MultitoolCLI` library target
// (`Sources/MultitoolCLI/CLIRunner.swift`) so it's directly testable from
// this package's unit tests and from the nested integration package; this
// file is just the process entry point.
//
// A library rather than a plain executable because a package cannot depend on
// another package's executable target at all, and the integration suite in
// `IntegrationTests/` has to reach `CLIRunner`. `Package.swift` states the
// same split from the manifest side.
//
// The first statement bootstraps the telemetry backends, before the first log
// record: the OTLP exporters when `OTEL_EXPORTER_OTLP_ENDPOINT` is set, and a
// log handler that writes to standard error when it is not. Standard output
// carries only the answers.
//
// Then the process watches `SIGINT` and `SIGTERM`, starts the export services,
// and runs the command through `CLIExitPath`, the one exit path. Each end of
// the run goes through it: each exit code of the command, an error that the
// command throws, and a stop signal. The path ends the run span, flushes the
// exporters within its bound, and gives the exit code. The `exit` below is the
// only exit of the process, and it comes after the flush.
//
// A literal `main.swift` supports top-level `await` directly (no `@main`
// type needed), so the entry point is exactly this.

import Foundation
import MultitoolCLI

let telemetry = TelemetryBootstrap.bootstrap()
let stopSignals = CLIStopSignal.makeSignalStream()
let arguments = Array(CommandLine.arguments.dropFirst())
let exitPath = CLIExitPath(flush: telemetry.start())
let exitCode = await exitPath.run(stoppingOn: stopSignals) { cancellation in
    await CLIRunner.run(arguments: arguments, cancellation: cancellation)
}
exit(exitCode)
