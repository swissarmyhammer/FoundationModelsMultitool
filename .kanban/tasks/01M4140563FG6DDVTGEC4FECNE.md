---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41gg3a9hhrrrxpn408h9m5b
  text: |-
    Research done.
    - Only the CLI targets link `mlx-swift-lm` (`liveLoaderMLXProducts`), `swift-otel` and `swift-service-lifecycle`. Remove all three package declarations from the root manifest. The integration manifest declares `mlx-swift-lm` itself; move the `MLXVLM` reason text there, because the root comment it points to goes away.
    - `OutputCollector` has only CLI users. Delete it.
    - After the two CLI integration suites go, no integration test uses `RootProduct` or the root `mcp-test-server` binary. The user decided (question tool, 2026-10-03): "if there is dead code, then delete it". Thus delete all of `RootProduct.swift`, the whole `integration-root-products` input of ci.yml with its comment, and the CIWorkflowTests test for that line.
  timestamp: 2026-10-03T18:30:21.769363+00:00
- actor: claude-code
  id: 01m41h7yrbr2hae4vq4a9rqv4v
  text: |-
    Implementation landed.
    - RED then GREEN: new test `PackageManifestTests.theOneExecutableTargetIsTheTestServer` failed on the `cliTargetName` executable, and passes after the deletion. Removed the tests `applicationTargetDeclaresRouter`, `onlyTheExecutableLinksOTel` and `sharedCallNamesRootProductIntegrationSuiteStarts`.
    - Root manifest: removed both CLI targets, the `MultitoolCLI` product, `mlx-swift-lm`, `swift-otel` and `swift-service-lifecycle`. `swissArmyHammerPackage(name:)` lost its `branch:` parameter, because no caller passed one now.
    - Dead code that the user said to delete (2026-10-03): `RootProduct.swift`, the `integration-root-products` CI input, `OutputCollector.swift`, `GatedServerMaker.swift`, and the `ServerMode.stall` mode with `answersRequests`, `readInputToEnd` and its test (CLI-only; main.swift is again the form before commit f051edf).
    - Doc comments updated in README.md, docs/SECURITY.md (CLI reference only), SampleSnippet.swift, SearchToolsTool+Seams.swift, MultiToolConfiguration.swift, ExamplesTests.swift, IntegrationTests/Package.swift, LiveRouterFixture.swift and MetalLibraryTestBootstrap.swift.
    - Note: the literal acceptance `rg` also matches `.kanban/` task text (this card holds the names). Outside `.kanban/` it finds nothing.
    - Note: each build prints `warning: missing creator for mutated node` for the mlx-swift_Cmlx bundle. It is a SwiftPM warning of the mlx dependency, not of this code.

    ### implement — changed
    - evidence: 43 files (25 deleted with git rm, 18 changed). `swift build` OK; `swift test` 1809 tests in 151 suites passed; `cd IntegrationTests && swift build --build-tests` OK; `swift package describe` lists no `multitool-cli`.
    - next: /review
  timestamp: 2026-10-03T18:43:23.531383+00:00
depends_on:
- 01M414E25TM8256CRYPKADAA1Q
position_column: doing
position_ordinal: '8180'
title: Delete the MultitoolCLI library, the multitool-cli executable, and their tests
---
## What
Decision of the user: the package does not need a Multitool CLI. Deleting it also removes the CLI mail-drain clock (`CLIMailWait.timeLimit`, `CLIExitPath` flush bound), which conflicted with the `runCode` tool timeout. `^kadaa1q` first moves the parts that the integration tests use.

This task touches many files, but most of them are deletions of one concern. The build only compiles when the target and its tests go together.

Subtasks:
- [x] `Package.swift`: remove `cliLibraryTargetName` (`MultitoolCLI`), `cliTargetName` (`multitool-cli`), the `.executable` product (near line 510), both targets (near lines 621 and 691), and each dependency that only they use (for example the swift-otel products; check the MLX products named for the CLI). Delete `Sources/MultitoolCLI/` and `Sources/multitool-cli/`.
- [x] Delete the CLI unit tests in `Tests/FoundationModelsMultitoolTests/`: `CLIAnswerDrainTests.swift`, `CLIArgumentTests.swift`, `CLIArgumentTests+Web.swift`, `CLITelemetryBootstrapTests.swift`, `CLITelemetryShutdownTests.swift`, `DemoProfileTests.swift`. Update `PackageManifestTests.swift` (remove the CLI target and swift-otel tests), `ExamplesTests.swift`, `Support/GatedServerMaker.swift`, `Tests/Support/MCPTestServer/ServerMode.swift` (the CLI-only mode, if nothing else uses it) and `Tests/Support/MultitoolTestSupport/OutputCollector.swift` (delete it if only CLI tests use it).
- [x] Integration tests: delete `CLISmokeTests.swift`, `CLISignalExitTests.swift`, `Support/OTLPTestCollector.swift`, and `RootProduct.cliName`. Remove the `MultitoolCLI` product dependency from `IntegrationTests/Package.swift` (near line 150) and its comment.
- [x] CI: in `.github/workflows/ci.yml` (near lines 68-85), remove `multitool-cli` from `integration-root-products` and the comments about the CLI. Update `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` (near line 93).
- [x] Docs: remove the CLI sections of `README.md` (near lines 50 and 247-253) and the CLI reference in `docs/SECURITY.md` (near line 213). Fix the doc comments that name `MultitoolCLI` or `RouterDiscoverySeams` as a CLI part in `Sources/FoundationModelsMultitool/Discovery/SampleSnippet.swift` (near line 35) and `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool+Seams.swift` (near lines 8 and 97). Leave historical plan files (`plan.md`, `eventplan.md`, `web.md`) as they are.

## Acceptance Criteria
- [x] `rg -n -i "MultitoolCLI|multitool-cli|CLIRunner|CLIMailWait|CLIExitPath" --glob '!plan.md' --glob '!eventplan.md' --glob '!web.md' --glob '!.build/**' .` finds nothing.
- [x] `swift package describe` lists no executable product named `multitool-cli`.

## Tests
- [x] `swift build` and `swift test` pass in the root package.
- [x] `cd IntegrationTests && swift build --build-tests` passes.
- [x] `CIWorkflowTests` and `PackageManifestTests` pass with the new expectations.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cleanup #timeouts