---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Move the Router discovery seams and the demo model pins out of MultitoolCLI into integration-test support
---
## What
Decision of the user: the package does not need a Multitool CLI. The `MultitoolCLI` library and the `multitool-cli` executable will be deleted (`^c4fecne`). Before that, the integration tests must stop importing `MultitoolCLI`. Today they use these parts of it:

- `CLIRunner.demoProfile`, `CLIRunner.flashModel`, `CLIRunner.embeddingModel` (and `CLIRunner.generationModel`, which `demoProfile` uses) — `Sources/MultitoolCLI/CLIRunner.swift:466-495`. Used in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift:372, 433, 454, 474, 498`.
- `RouterDiscoverySeams` (`Sources/MultitoolCLI/RouterDiscoverySeams.swift`), with `RoutedAgentSession` and `SameModelDiscoveryError` (`Sources/MultitoolCLI/RoutedAgentSession.swift`). Used in `LiveRouterFixture.swift:598-599, 681`.

The core library does not link Router (README.md near line 50). Thus this Router glue moves into the integration-test target, not into the library.

Subtasks:
- [ ] Move `RouterDiscoverySeams.swift` and `RoutedAgentSession.swift` to `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/`. Make them `internal`. Remove the doc text about `CLIRunner`.
- [ ] Put the model pins and the profile in `LiveRouterFixture.swift` as the single source (for example `generationModel`, `flashModel`, `embeddingModel`, `multitoolTinyProfile`), copied from `CLIRunner.swift:466-495`. Update every doc comment that says `CLIRunner.*` (find them with `rg -n "CLIRunner" IntegrationTests`).
- [ ] Move the unit tests of the seams, `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift`, into the integration-test target if they do not load a model, or delete them if the integration suites already cover them.
- [ ] The CLI-only integration suites (`CLISmokeTests.swift`, `CLISignalExitTests.swift`, `Support/OTLPTestCollector.swift`, `RootProduct.cliName`) still import `MultitoolCLI`. Do not change them in this task. `^c4fecne` deletes them.

## Acceptance Criteria
- [ ] `rg -n "CLIRunner|import MultitoolCLI" IntegrationTests/Tests --glob '!CLISmokeTests.swift' --glob '!CLISignalExitTests.swift' --glob '!OTLPTestCollector.swift'` finds nothing.
- [ ] The model pins appear in one place only in the integration-test target.

## Tests
- [ ] `cd IntegrationTests && swift build --build-tests` passes.
- [ ] The integration suites that use `discoverySeams` (for example `OverBudgetSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `WebResearchScenarioTests`) pass in CI.
- [ ] `swift test` in the root package passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cleanup #router #timeouts