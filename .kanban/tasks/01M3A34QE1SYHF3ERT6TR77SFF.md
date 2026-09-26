---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3czqs7576exq1t0yncp0znn
  text: |-
    Research notes.
    - `FilesBareSessionTests` uses `runBareSessionScenario`, which mounts plain tools on a bare `LanguageModelSession` with `SystemLanguageModel.default`. That path does not queue behind `liveProfileTurnstile` and has no call record. The card requires the turnstile and a call record, so the scenario uses the Router path: `withLiveRouterFixture` (it takes `liveProfileTurnstile` in `LiveRouterFixture.resolve`), `registry.makeSessionTools(librarian:)`, a `RoutedSession` from `.standard`, and `streamTurn`. This is the same wiring as `ShellBackgroundRunner` and `OperationToolLiveTests`.
    - `ScenarioCallLog` records fixture tools only (each fixture tool calls `recordCall(to:)`). The web verbs are product verbs, so they cannot write to it. `OperationToolLiveTests` states the same limit and reads `StreamedTurn.calls` instead. This scenario does the same: the check reads the `tools.*` call paths of each `runCode` snippet in `StreamedTurn.calls` through `NativeTranscript.typedToolPaths(in:)`, and requires `web.search`.
    - Inner `tools.*` calls post `ToolInvocationRecord` values through Router, but no test of this repository reads them for an inner call, so that path was not used as the grade.
    - `withWeb(configuration:sessionConfiguration:)` takes a `URLSessionConfiguration`. The scenario gives `.ephemeral` with short request and resource timeouts, so a slow provider cannot use the whole time limit.
  timestamp: 2026-09-25T19:12:39.141730+00:00
- actor: claude-code
  id: 01m3czwqcnfz22y74d0r7cjc8q
  text: |-
    Implementation landed in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/WebResearchScenarioTests.swift` (161 lines).
    - Mount: `MultiTool.Builder().withWeb(configuration: .keyless, sessionConfiguration:)` with `.ephemeral` and short timeouts (15 s request, 30 s resource), vended through `makeSessionTools(librarian:)` on the `.standard` `RoutedSession` of `withLiveRouterFixture` (queues behind `liveProfileTurnstile`). `.timeLimit(.minutes(12))`, `.serialized`, the same as `OperationToolLiveTests`.
    - Grade: `searchedTheWeb` (a `runCode` snippet in `StreamedTurn.calls` wrote `tools.web.search`, read with `NativeTranscript.typedToolPaths(in:)`) and `validAnswer` (`answerChecks` with `swift.org`). Trace lines go through `grade(scenario:checks:)` and `reportGatedResult(scenario:line:)` only.
    - `swift build --package-path IntegrationTests --build-tests`: Build complete. The one warning is the SwiftPM build-system line "missing creator for mutated node ... mlx-swift_Cmlx.bundle/Contents/MacOS". It names the mlx resource bundle output, not a source file of this change. I did not do a build without this change to compare.
    - `swift test --package-path IntegrationTests --no-parallel --filter WebResearchScenarioTests`: 1 test passed in 41.6 s. Route: searchTools, runCode (`tools.web.search`), wait, runCode (`tools.web.fetch`). Reply "https://www.swift.org/". `SCENARIO [webResearch] result=PASS searchedTheWeb=pass validAnswer=pass`.
    - `rg -n 'ProcessInfo.processInfo.environment|fromEnvironment' IntegrationTests`: no match.
    - TDD note: the card's test is an integration scenario. The TDD skill keeps integration tests out of the red-green loop, and no production code changed, so no unit test was added.

    ### implement — changed
    - evidence: 1 file — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/WebResearchScenarioTests.swift; build-tests complete; scenario 1/1 passed; rg gives no match
    - next: review
  timestamp: 2026-09-25T19:15:21.109649+00:00
- actor: claude-code
  id: 01m3d00hvnb2d77jrpbjsr11cb
  text: |-
    ### test — green
    - evidence: `swift test` — 1790 tests, 143 suites, 0 failed, 0 skipped. `swift build --build-tests --package-path IntegrationTests` — build OK, 0 warnings in repo code.
    - note: one warning is present, `missing creator for mutated node` for `mlx-swift_Cmlx.bundle`. This warning is from the vendored mlx-swift dependency under `.build`. It is not part of this repository's code. It does not change the outcome.
    - next: none. The build is clean.
  timestamp: 2026-09-25T19:17:26.517096+00:00
- actor: claude-code
  id: 01m3d06zskmvjwdv3g20cbt22m
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit baf5a81). The engine reviewed 1 file (WebResearchScenarioTests.swift). Counts: 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. The 4 `.kanban/` files are excluded by `.reviewignore`. The commit renames no file.
    - next: The task is in done. No work remains.
  timestamp: 2026-09-25T19:20:57.395884+00:00
- actor: claude-code
  id: 01m3d07aa651rxssznd5z5w480
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file; the scenario passed one live run (real model, keyless web)
    - test: green — swift test, 1790 passed; IntegrationTests build passes
    - commit: baf5a81
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-25T19:21:08.166798+00:00
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: done
position_ordinal: ffe380
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
- [x] `swift build --package-path IntegrationTests --build-tests` succeeds.
- [x] The scenario passes on a machine that has the demo profile and network access.
- [x] No file of `IntegrationTests/` reads the process environment.

## Tests
- [x] The scenario file above.
- [x] Run `swift build --package-path IntegrationTests --build-tests`. It succeeds.
- [x] Run `swift test --package-path IntegrationTests --no-parallel --filter WebResearchScenarioTests`. It passes.
- [x] Run `rg -n 'ProcessInfo.processInfo.environment|fromEnvironment' IntegrationTests`. It gives no match.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web