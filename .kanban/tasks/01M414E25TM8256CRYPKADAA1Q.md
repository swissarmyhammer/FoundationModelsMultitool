---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41cscj4xw0p1sqrx7scq9dz
  text: |-
    Research done. Findings:
    - `CLIRunner.runDemo` (Sources/MultitoolCLI/CLIRunner.swift) calls `RouterDiscoverySeams.acquireEmbedder` and `RouterDiscoverySeams(librarian:embedder:)`. Thus a true move of the seam files out of MultitoolCLI stops the CLI build. The user said: do not delete the CLI in this task. Thus the integration target gets its own internal copy, and the MultitoolCLI copy stays until ^c4fecne deletes `Sources/MultitoolCLI/`.
    - `RouterDiscoverySeams.makeSelection` uses `SelectionGrammar` (Sources/MultitoolCLI/SelectionGrammar.swift). The card does not name it, but the seams cannot compile without it. It goes to the integration Support folder too.
    - `RouterDiscoverySeamsTests` loads no model, so it moves. It needs a stub Router resolve (`makeStubProfile`, root Fixtures/StubRouterFixtures.swift), which the integration target does not have. Plan: a small Support file with a stub loader that reuses `LiveRouterFixture.makeRouter` and the `SizedMetadataSource` of RouterMetadataCacheTests. `TripCitiesTool`/`GithubCreateIssueTool` become the ScenarioGrading tools `IntegrationTripTool`/`IntegrationWeatherTool`.
    - `ProfileSlotSeparationTests` already holds standard and flash apart in the integration target. `DemoProfileTests` (root) stays for the CLI copy; ^c4fecne deletes it.
    - The profile name `multitool-cli-demo` would match the ^c4fecne acceptance search, so the integration profile gets a new name.
  timestamp: 2026-10-03T17:25:31.844768+00:00
- actor: claude-code
  id: 01m41dgqepngx94rjwt6pr6k4h
  text: |-
    Implementation landed. What changed:
    - New internal files in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/`: `RouterDiscoverySeams.swift`, `RoutedAgentSession.swift` (with `SameModelDiscoveryError`), `SelectionGrammar.swift`, and `StubRouterProfile.swift` (a stub Router resolve over `LiveRouterFixture.makeRouter`, for the seam tests; `SizedMetadataSource` moved here from `RouterMetadataCacheTests.swift` so both use one copy).
    - `LiveRouterFixture.swift` is the single source of `generationModel`, `flashModel`, `embeddingModel` and `multitoolTinyProfile` (profile name `multitool-tiny`, because `multitool-cli-demo` matches the ^c4fecne search). It no longer imports `MultitoolCLI`.
    - `RouterDiscoverySeamsTests.swift` moved with `git mv` from the root unit target to the integration target. It loads no model. `TripCitiesTool`/`GithubCreateIssueTool` became `IntegrationTripTool`/`IntegrationWeatherTool`; the fail session and the error are private types of the file.
    - New model-free test `ProfileSlotSeparationTests.tinyProfileSlotsNameTheirPins` (RED: `generationModel`, `flashModel`, `embeddingModel` not in scope; GREEN after the pins).
    - Every `CLIRunner.*` doc comment in the integration target is rewritten. Root docs that became false are corrected: `Package.swift` (`cliLibraryTargetName`, `liveLoaderMLXProducts`), `CLIRunner.swift` (the pin docs; `flashModel`, `embeddingModel`, `demoProfile` are now `internal`, because no other module reads them), `DiscoveryEmbedderTests.swift`.
    - Root `StubRouterFixtures.makeStubProfile` lost its `embeddingModel:` and `pool:` parameters: the moved seam tests were their only callers.

    KNOWN DUPLICATION, by the order of the user: the MultitoolCLI copies of `RouterDiscoverySeams`, `RoutedAgentSession`, `SameModelDiscoveryError`, `SelectionGrammar` and the three model pins stay, because `CLIRunner.runDemo` uses them and the user said not to delete the CLI in this task. The integration target cannot import a shared copy without `import MultitoolCLI`, which the acceptance criteria forbid. ^c4fecne deletes `Sources/MultitoolCLI/` and with it the second copy. A duplication finding on these pairs is this known state, not an accident.

    Not run: live model tests and live web tests (by instruction). The build prints `warning: missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')`. It is a build-system message about the mlx-swift resource bundle, not a compiler warning, and no change of this task touches that bundle.
  timestamp: 2026-10-03T17:38:16.662135+00:00
- actor: claude-code
  id: 01m41dhh05fjq6zthnsm2h1kwh
  text: |-
    ### implement — changed
    - evidence: 20 files. New: IntegrationTests/.../Support/{RouterDiscoverySeams,RoutedAgentSession,SelectionGrammar,StubRouterProfile}.swift. Moved: Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift -> IntegrationTests/.../RouterDiscoverySeamsTests.swift. Changed: IntegrationTests/Package.swift; IntegrationTests/.../{AgentSurfaceDiscoveryTests,OverBudgetSurfaceDiscoveryTests,ProfileSlotSeparationTests,RetrievalTextSurfaceDiscoveryTests,RouterMetadataCacheTests,UnknownToolHintLiveTests,WebResearchScenarioTests}.swift; IntegrationTests/.../Support/{LiveRouterFixture,ScenarioRunner,ShellBackgroundRunner}.swift; Package.swift; Sources/MultitoolCLI/CLIRunner.swift; Tests/FoundationModelsMultitoolTests/{DiscoveryEmbedderTests,Fixtures/StubRouterFixtures}.swift.
    - `swift build --build-tests` (root): pass. `swift test` (root): 1877 tests in 156 suites passed.
    - `cd IntegrationTests && swift build --build-tests`: pass. `swift test --skip-build --no-parallel --filter "RouterDiscoverySeamsTests|ProfileSlotSeparationTests|RouterMetadataCacheTests"` (model-free): 18 tests in 3 suites passed. Live model and live web tests not run, by instruction.
    - Acceptance rg (`CLIRunner|import MultitoolCLI`, three CLI files excluded): no match. Pins: one line each, in Support/LiveRouterFixture.swift.
    - next: /review. Expect duplication rows between the integration Support seam files and Sources/MultitoolCLI; see the comment above — known state until ^c4fecne.
  timestamp: 2026-10-03T17:38:42.821187+00:00
position_column: doing
position_ordinal: '8180'
title: Move the Router discovery seams and the demo model pins out of MultitoolCLI into integration-test support
---
## What
Decision of the user: the package does not need a Multitool CLI. The `MultitoolCLI` library and the `multitool-cli` executable will be deleted (`^c4fecne`). Before that, the integration tests must stop importing `MultitoolCLI`. Today they use these parts of it:

- `CLIRunner.demoProfile`, `CLIRunner.flashModel`, `CLIRunner.embeddingModel` (and `CLIRunner.generationModel`, which `demoProfile` uses) — `Sources/MultitoolCLI/CLIRunner.swift:466-495`. Used in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift:372, 433, 454, 474, 498`.
- `RouterDiscoverySeams` (`Sources/MultitoolCLI/RouterDiscoverySeams.swift`), with `RoutedAgentSession` and `SameModelDiscoveryError` (`Sources/MultitoolCLI/RoutedAgentSession.swift`). Used in `LiveRouterFixture.swift:598-599, 681`.

The core library does not link Router (README.md near line 50). Thus this Router glue moves into the integration-test target, not into the library.

Subtasks:
- [x] Move `RouterDiscoverySeams.swift` and `RoutedAgentSession.swift` to `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/`. Make them `internal`. Remove the doc text about `CLIRunner`.
- [x] Put the model pins and the profile in `LiveRouterFixture.swift` as the single source (for example `generationModel`, `flashModel`, `embeddingModel`, `multitoolTinyProfile`), copied from `CLIRunner.swift:466-495`. Update every doc comment that says `CLIRunner.*` (find them with `rg -n "CLIRunner" IntegrationTests`).
- [x] Move the unit tests of the seams, `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift`, into the integration-test target if they do not load a model, or delete them if the integration suites already cover them.
- [x] The CLI-only integration suites (`CLISmokeTests.swift`, `CLISignalExitTests.swift`, `Support/OTLPTestCollector.swift`, `RootProduct.cliName`) still import `MultitoolCLI`. Do not change them in this task. `^c4fecne` deletes them.

## Acceptance Criteria
- [x] `rg -n "CLIRunner|import MultitoolCLI" IntegrationTests/Tests --glob '!CLISmokeTests.swift' --glob '!CLISignalExitTests.swift' --glob '!OTLPTestCollector.swift'` finds nothing.
- [x] The model pins appear in one place only in the integration-test target.

## Tests
- [x] `cd IntegrationTests && swift build --build-tests` passes.
- [ ] The integration suites that use `discoverySeams` (for example `OverBudgetSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `WebResearchScenarioTests`) pass in CI.
- [x] `swift test` in the root package passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cleanup #router #timeouts