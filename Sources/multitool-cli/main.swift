// multitool-cli
//
// A runnable demonstration of the whole FoundationModelsMultitool pipeline:
// Router profile resolution -> a RoutedSession over the resolved .standard
// slot, carrying multiTool, wait and (unless --direct) searchToolsTool ->
// one demo prompt, driven by draining the session's event stream.
// All the actual logic lives in `CLIRunner` (`CLIRunner.swift`) so it's
// directly unit-testable; this file is just the process entry point.
//
// A literal `main.swift` supports top-level `await` directly (no `@main`
// type needed), so the entry point is exactly this.

import Foundation

let exitStatus = await CLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitStatus)
