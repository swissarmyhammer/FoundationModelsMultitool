---
assignees:
- claude-code
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: todo
position_ordinal: 8f80
title: 'Web: add the real-model web research scenario (WebResearchScenarioTests)'
---
## What
Prove that a real model uses the web capability in one live scenario. Design: `web.md` § "Testing / Level 3".

- Create `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/WebResearchScenarioTests.swift`, modelled on `FilesBareSessionTests.swift` and the `ScenarioGrading` harness it uses.
- Mount `.withWeb(configuration: .keyless)`. `.keyless` reads no environment, so the rule of `IntegrationTests/Package.swift:41-44` ("nothing here reads the environment") stays true. Do not use `.fromEnvironment()` or `withWeb()` with its default in this package.
- Prompt: "Find the address of the home page of the Swift programming language on the web. Answer with the URL only."
- Grade: the call log has a `tools.web.search` call, and the final answer contains `swift.org`.
- The scenario queues behind `liveProfileTurnstile` (`Support/LiveRouterFixture.swift:503`), the same as each other scenario, with the same `.timeLimit` pattern.

## Acceptance Criteria
- [ ] `swift build --package-path IntegrationTests --build-tests` succeeds.
- [ ] The scenario passes on a machine that has the demo profile and network access.
- [ ] No file of `IntegrationTests/` reads the process environment.

## Tests
- [ ] The scenario file above.
- [ ] Run `swift build --package-path IntegrationTests --build-tests`. It succeeds.
- [ ] Run `swift test --package-path IntegrationTests --no-parallel --filter WebResearchScenarioTests`. It passes.
- [ ] Run `rg -n 'ProcessInfo.processInfo.environment|fromEnvironment' IntegrationTests`. It gives no match.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web