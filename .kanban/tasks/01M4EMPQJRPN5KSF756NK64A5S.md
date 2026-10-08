---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4eqyfg3701ph16pbadp1j95
  text: |-
    Research: the only users of `correctionField` and `runCodeOutputs(of:)` in GitScenarioTests.swift were `checks(turn:)`. The shared `ScenarioCheck.noCorrection(named:in:)` uses the same regex and the same runCode filter, thus the `held` value is the same. One difference: the failure message now joins the corrected outputs with " | " (the shared form) and does not print a Swift array. No test pins that message.

    Note: the `dump validators` file for one .swift path is approximately 750 KB. I read the rule headings, not the full body.

    Note: the kanban `move task` and `update task` results are approximately 100 KB each and overflow the tool output limit. The operations completed.
  timestamp: 2026-10-08T21:50:40.643994+00:00
- actor: claude-code
  id: 01m4eqyj9ba6jk1gp92vn5f97f
  text: |-
    ### implement — changed
    - evidence: 1 file — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/GitScenarioTests.swift (removed `correctionField`, `runCodeOutputs(of:)`, and the inline check; `checks(turn:)` calls `ScenarioCheck.noCorrection(named:in:)`). `swift build --package-path IntegrationTests --build-tests` OK, no source warning (only the SwiftPM "missing creator for mutated node" note about the mlx-swift_Cmlx bundle, which is not in a test file). NoCorrectionCheckTests 3/3 pass. GitScenarioTests live 1/1 pass (Qwen3.8-27B, 21.4 s, calledTheVerbs=pass noCorrection=pass). Root `swift build --build-tests` OK; root `swift test` 2324 tests in 205 suites pass.
    - next: /review
  timestamp: 2026-10-08T21:50:43.499811+00:00
- actor: claude-code
  id: 01m4erdcfqp2jqm6f1tg8qrtkv
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (2b9a655): 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed. Reviewed file: IntegrationTests/.../GitScenarioTests.swift. The .kanban files are not in scope (.reviewignore).
    - next: none. The task moved to done.
  timestamp: 2026-10-08T21:58:49.079430+00:00
- actor: claude-code
  id: 01m4erds5j7a942eaamn5s0bj2
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — GitScenarioTests.swift
    - test: green — root swift test 2324 passed; IntegrationTests 4 passed (live)
    - commit: 2b9a655
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-08T21:59:02.066261+00:00
position_column: done
position_ordinal: ffffcf80
title: Move GitScenarioTests onto the shared ScenarioCheck.noCorrection check
---
## What
Task `^w2kryyf` added `ScenarioCheck.noCorrection(named:in:)` to `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/GatedTurnScenario.swift`. `GitScenarioTests.swift` still has its own private copy of the same check: `correctionField`, `runCodeOutputs(of:)`, and the `noCorrection` `ScenarioCheck` in `checks(turn:)`. The duplication rule says not to edit the counterpart in the change that adds the shared form, thus this task does it.

- In `GitScenarioTests.swift`, call `ScenarioCheck.noCorrection(named: noCorrectionCheckName, in: turn)` in `checks(turn:)`.
- Remove `correctionField` and `runCodeOutputs(of:)` from `GitScenarioTests.swift`.

## Acceptance Criteria
- [x] `GitScenarioTests.swift` holds no copy of the correction check.
- [x] `NoCorrectionCheckTests` stays green.

## Tests
- [x] `swift build --package-path IntegrationTests --build-tests` builds with no warning in the test files.
- [x] Run `swift test --package-path IntegrationTests --no-parallel --filter GitScenarioTests` — the scenario passes. #environment