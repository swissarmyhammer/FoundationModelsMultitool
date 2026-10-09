---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Make the background shell scenario follow the settle-period rule (CI integration failure)
---
## What
CI run 37927608237 (commit c8c74ba), job "Integration (opt-in, real dependencies)", failed 1 of 113 tests:
`✘ Test "a shell command goes to the background, stands on the run plane, is read live, is stopped, and is journaled" recorded an issue at ScenarioRunner.swift:732:9: Expectation failed: check.held` (2 issues).

RESULT line: `backgroundToken=none backgroundReports=0 background=execute/execute shell/process declaredOp=execute shell liveLines=2 processGroup=47187 cancel=stopped childGone=true sweptRun=01M4GA0YA5WBXH5TQ3T6GPK18Q journaledEvents=9 sweptTerminals=1 ... reply="The command is running in the background and handed back the completion token **01M4GA0Y38HZK62EFTZBCCQ39D**."`

Cause: the settle-period rule of task ^38j4bbn (Extras c18a9aa, Multitool 89bc1ca). The scenario (`IntegrationTests/.../Support/ShellBackgroundRunner.swift` and `shellBackgroundChecks(for:)`) expects the OUTER `runCode` call to go to the background and hand back a pending envelope. Now the inner `tools.shell.execute` of the endless command waits for its settle period (clipped to end before the outer period), gives the snippet `{pending: true, commandID, ...}`, the snippet ends inside the outer period, and the outer call answers with its own result. The command run itself still goes to the background, is read live, is stopped and is journaled.

Fix the scenario, not the rule: take the background token from the `execute` run (the `commandID` / completionToken of the pending object that the snippet returns, or the run plane), and check the background path through that run. Update the suite doc comment that says "the outer run goes to the background and hands back a pending envelope".

## Acceptance Criteria
- [ ] The scenario finds the background run of the shell command without an outer pending envelope.
- [ ] Every other check of the scenario (live read, stop, child gone, journal, sweep) still holds.
- [ ] No check depends on a fixed model wording or a fixed model score.

## Tests
- [ ] Run the scenario live in IntegrationTests (`swift test --filter <the shell background suite>`) and see it pass.
- [ ] Root `swift test` passes.

## Workflow
- Use `/tdd` where a model-free check can show the failure first.