// multitool-cli
//
// A runnable demonstration of the whole FoundationModelsMultitool pipeline:
// Router profile resolution -> a RoutedSession over the resolved .standard
// slot, carrying multiTool, wait and (unless --direct) searchToolsTool ->
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
// A literal `main.swift` supports top-level `await` directly (no `@main`
// type needed), so the entry point is exactly this.

import Foundation

import MultitoolCLI

let exitStatus = await CLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitStatus)
