// multitool-cli
//
// A runnable demonstration of the whole FoundationModelsMultitool pipeline:
// Router profile resolution -> wrapping the resolved model as a real
// FoundationModels.LanguageModel (MLXLanguageModel) -> a native
// LanguageModelSession registering multiTool and (unless --direct)
// findAPIsTool, driven by Apple's own tool-calling loop for one demo prompt.
// All the actual logic lives in `CLIRunner` (`CLIRunner.swift`) so it's
// directly unit-testable; this file is just the process entry point.
//
// A literal `main.swift` supports top-level `await` directly (no `@main`
// type needed), so the entry point is exactly this.

import Foundation

let exitStatus = await CLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitStatus)
