---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4em14nk9whanzg8ww1j8h6n
  text: |-
    Research done.
    - `GitScenarioTests` is the model. `runGatedTurnScenario(named:prompt:tools:reading:)` and `calledTheVerbsCheck` are in `Support/GatedTurnScenario.swift`.
    - The internal `MultiTool.Builder.withEnvironment(context:)` and `EnvironmentContext(now:timeZone:)` are visible through `@testable import`. Thus the scenario injects a fixed clock and a fixed time zone.
    - User rule overrides the card text: the card says the RESULT line prints whether the answer names the real weekday from `Date()`, and no test asserts it. The user rule says: inject the clock and the time zone, and assert that the answer holds the injected date. The scenario injects 2030-06-12T15:00:00Z in Europe/Paris (Wednesday, 2030-06-12) and asserts that the answer names "Wednesday" or "2030-06-12".
    - The no-correction check of `GitScenarioTests` is private. To avoid a copy, the shared form goes into `Support/GatedTurnScenario.swift`. The duplication rule says not to edit the counterpart, thus a new task moves `GitScenarioTests` onto the shared check.
  timestamp: 2026-10-08T20:42:13.555442+00:00
- actor: claude-code
  id: 01m4emq5s24deqf0eqbbm5f9m3
  text: |-
    ### implement — changed
    - evidence: new `EnvironmentScenarioTests.swift` (live scenario + offline `InjectedDateTests`, 4 tests), new `NoCorrectionCheckTests.swift` (3 tests), `Support/GatedTurnScenario.swift` (shared `ScenarioCheck.noCorrection(named:in:)`), `Support/ScenarioRunner.swift` (adds `.runProgress` to the ignored event list).
    - RED: `swift build --build-tests` in IntegrationTests failed with "type 'ScenarioCheck' has no member 'noCorrection'". GREEN: 7 offline tests pass.
    - Live run on this machine: `swift test --no-parallel --filter EnvironmentScenarioTests` in IntegrationTests passed in 43.6 s. RESULT: toolCalls=2 (searchTools, runCode), typed=[environment.now, environment.os], reply "Today is Wednesday (June 12, 2030), and this is macOS (version 27.0.1, arm64)."
    - Root: `swift build --build-tests` has no source warning (one SwiftPM "missing creator for mutated node" note from the mlx bundle, from before this change). `swift test`: 2321 tests in 203 suites passed.
    - Discovery: after `swift package update`, Router main adds `SessionEvent.runProgress`. The exhaustive switch in `ScenarioRunner.streamTurn` did not compile. I added the case to the ignored list, because the package did not build without it.
    - User rule override: the scenario injects the clock and the time zone (2030-06-12T15:00:00Z, Europe/Paris) and asserts that the answer names "Wednesday" or "2030-06-12". The card said only to print the real weekday.
    - Follow-up: ^nk64a5s moves `GitScenarioTests` onto the shared check.
    - next: /review
  timestamp: 2026-10-08T20:54:15.586167+00:00
depends_on:
- 01M4E1XR9RGN1BNPYHWDKT9H63
- 01M4E2HPENAVR0VT8MWC73RK0S
position_column: doing
position_ordinal: '80'
title: Add a gated scenario where a real model reads the date through tools.environment
---
## What
Add one gated integration scenario that proves a real model uses the environment capability in a `runCode` snippet.

File to create:
- `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/EnvironmentScenarioTests.swift` — model it on `GitScenarioTests.swift`:
  - Mount `MultiTool.Builder().withEnvironment()` through `makeSessionTools(of:on:)` and `runGatedTurnScenario(named:prompt:tools:reading:)`.
  - One short prompt, thus one model turn, for example: "What day of the week is it today, and which operating system is this? Answer in one short sentence."
  - The grade asserts code properties only (no fixed model score):
    1. A `runCode` snippet of the turn called `environment.now` (read through `NativeTranscript.typedToolPaths(in:)`).
    2. No `runCode` output holds a `correction`.
  - The `RESULT` line prints whether the answer names the real weekday (from `Date()` at the test run). No test asserts that value.

The scenario runs on each push. There is no skip and no second round. The whole integration job must stay in 20 minutes.

Write comments in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [x] The scenario mounts only the environment capability and runs one model turn.
- [x] It asserts that `environment.now` was called and that no output holds a `correction`.
- [x] It prints a `RESULT` line and asserts no model score.

## Tests
- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/EnvironmentScenarioTests.swift` — the scenario above.
- [x] Run `swift test` in `IntegrationTests/` (after `swift package update`) — the new scenario passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment