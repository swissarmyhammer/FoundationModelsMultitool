---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Remaining real-clock time checks after the "no load testing" decision
---
## What
Card ^tm4x2hp applied the user decision "no test checks the speed of the machine" to the root tests and to each integration `.timeLimit`. These real-clock time checks stay, and a person must decide each one:

- `IntegrationTests/.../SelectionForkPerCallTests.swift`: asserts `second <= first` on two real durations. It is a speed check on purpose (a measurement of the second call).
- `Tests/Support/ScenarioGrading/ScenarioGrading.swift` check `nestedRefusalInTime`: the refusal of a nested generation must come in `integrationNestedRefusalTimeLimit` (5 s, real clock), in `NestedGenerationProbeTests`. A refusal at once is the defect it finds. A busy machine can make it fail.
- `Tests/FoundationModelsMultitoolTests/ResilienceTests.swift` `explicitConnectDuringInFlightReconnectWins`: depends on a real 10 s per-attempt timeout and a 6 s sleep. `MCPServer.connectAttemptClock` (new in ^tm4x2hp) can gate it.
- `IntegrationTests/.../Support/ShellBackgroundRunner.swift` and `CLISignalExitTests.swift`: `IntegrationPoll` / `TestPoll` waits with their own short real deadlines.

## Decide
- For each item: convert it to an injected clock or an event, or keep it with a written decision.

## Acceptance Criteria
- [ ] Each item above is converted, or the card records the decision of a person for it.

## Tests
- [ ] Root `swift test` passes.