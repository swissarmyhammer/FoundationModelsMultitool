---
assignees:
- claude-code
depends_on:
- 01M4E1XR9RGN1BNPYHWDKT9H63
- 01M4E2HPENAVR0VT8MWC73RK0S
position_column: todo
position_ordinal: '8580'
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
- [ ] The scenario mounts only the environment capability and runs one model turn.
- [ ] It asserts that `environment.now` was called and that no output holds a `correction`.
- [ ] It prints a `RESULT` line and asserts no model score.

## Tests
- [ ] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/EnvironmentScenarioTests.swift` — the scenario above.
- [ ] Run `swift test` in `IntegrationTests/` (after `swift package update`) — the new scenario passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment