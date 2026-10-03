---
assignees:
- claude-code
depends_on:
- 01M414E25TM8256CRYPKADAA1Q
position_column: todo
position_ordinal: '8580'
title: Delete the MultitoolCLI library, the multitool-cli executable, and their tests
---
## What
Decision of the user: the package does not need a Multitool CLI. Deleting it also removes the CLI mail-drain clock (`CLIMailWait.timeLimit`, `CLIExitPath` flush bound), which conflicted with the `runCode` tool timeout. `^kadaa1q` first moves the parts that the integration tests use.

This task touches many files, but most of them are deletions of one concern. The build only compiles when the target and its tests go together.

Subtasks:
- [ ] `Package.swift`: remove `cliLibraryTargetName` (`MultitoolCLI`), `cliTargetName` (`multitool-cli`), the `.executable` product (near line 510), both targets (near lines 621 and 691), and each dependency that only they use (for example the swift-otel products; check the MLX products named for the CLI). Delete `Sources/MultitoolCLI/` and `Sources/multitool-cli/`.
- [ ] Delete the CLI unit tests in `Tests/FoundationModelsMultitoolTests/`: `CLIAnswerDrainTests.swift`, `CLIArgumentTests.swift`, `CLIArgumentTests+Web.swift`, `CLITelemetryBootstrapTests.swift`, `CLITelemetryShutdownTests.swift`, `DemoProfileTests.swift`. Update `PackageManifestTests.swift` (remove the CLI target and swift-otel tests), `ExamplesTests.swift`, `Support/GatedServerMaker.swift`, `Tests/Support/MCPTestServer/ServerMode.swift` (the CLI-only mode, if nothing else uses it) and `Tests/Support/MultitoolTestSupport/OutputCollector.swift` (delete it if only CLI tests use it).
- [ ] Integration tests: delete `CLISmokeTests.swift`, `CLISignalExitTests.swift`, `Support/OTLPTestCollector.swift`, and `RootProduct.cliName`. Remove the `MultitoolCLI` product dependency from `IntegrationTests/Package.swift` (near line 150) and its comment.
- [ ] CI: in `.github/workflows/ci.yml` (near lines 68-85), remove `multitool-cli` from `integration-root-products` and the comments about the CLI. Update `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` (near line 93).
- [ ] Docs: remove the CLI sections of `README.md` (near lines 50 and 247-253) and the CLI reference in `docs/SECURITY.md` (near line 213). Fix the doc comments that name `MultitoolCLI` or `RouterDiscoverySeams` as a CLI part in `Sources/FoundationModelsMultitool/Discovery/SampleSnippet.swift` (near line 35) and `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool+Seams.swift` (near lines 8 and 97). Leave historical plan files (`plan.md`, `eventplan.md`, `web.md`) as they are.

## Acceptance Criteria
- [ ] `rg -n -i "MultitoolCLI|multitool-cli|CLIRunner|CLIMailWait|CLIExitPath" --glob '!plan.md' --glob '!eventplan.md' --glob '!web.md' --glob '!.build/**' .` finds nothing.
- [ ] `swift package describe` lists no executable product named `multitool-cli`.

## Tests
- [ ] `swift build` and `swift test` pass in the root package.
- [ ] `cd IntegrationTests && swift build --build-tests` passes.
- [ ] `CIWorkflowTests` and `PackageManifestTests` pass with the new expectations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #cleanup