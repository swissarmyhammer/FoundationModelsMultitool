// multitool-cli
//
// plan.md M9's sample executable: a runnable demonstration of the whole
// FoundationModelsMultitool pipeline (Router profile resolution -> a
// MultiToolAgent over a couple of demo tools -> one findAPIs-then-runCode
// prompt). All the actual logic lives in `CLIRunner` (`CLIRunner.swift`) so
// it's directly unit-testable; this file is just the process entry point.
//
// A literal `main.swift` supports top-level `await` directly (no `@main`
// type needed), so the entry point is exactly this.

import Foundation

let exitStatus = await CLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitStatus)
