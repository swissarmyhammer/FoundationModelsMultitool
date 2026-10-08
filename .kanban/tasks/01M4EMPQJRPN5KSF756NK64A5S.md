---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Move GitScenarioTests onto the shared ScenarioCheck.noCorrection check
---
## What
Task `^w2kryyf` added `ScenarioCheck.noCorrection(named:in:)` to `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/GatedTurnScenario.swift`. `GitScenarioTests.swift` still has its own private copy of the same check: `correctionField`, `runCodeOutputs(of:)`, and the `noCorrection` `ScenarioCheck` in `checks(turn:)`. The duplication rule says not to edit the counterpart in the change that adds the shared form, thus this task does it.

- In `GitScenarioTests.swift`, call `ScenarioCheck.noCorrection(named: noCorrectionCheckName, in: turn)` in `checks(turn:)`.
- Remove `correctionField` and `runCodeOutputs(of:)` from `GitScenarioTests.swift`.

## Acceptance Criteria
- [ ] `GitScenarioTests.swift` holds no copy of the correction check.
- [ ] `NoCorrectionCheckTests` stays green.

## Tests
- [ ] `swift build --package-path IntegrationTests --build-tests` builds with no warning in the test files.
- [ ] Run `swift test --package-path IntegrationTests --no-parallel --filter GitScenarioTests` — the scenario passes. #environment