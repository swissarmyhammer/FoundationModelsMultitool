---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gcedzwq5arw5nmyv326ce1
  text: |-
    Research done.
    - The 2 failed checks in CI were `pendingEnvelope` (backgroundToken=none) and `backgroundReport` (0). All plane checks held.
    - `backgroundRunToken(in:)` reads the FIRST pending envelope in the turn's tool outputs. Under the settle-period rule the outer runCode settles, so no tool output is an envelope.
    - `BackgroundToolRunner.start` (Extras) posts one progress event with the rendered pending envelope for EVERY background run, inner runs too. An inner run posts through the outer context, so the event carries the OUTER runCode correlation. `SessionOutbox.withdrawStagedEvents` removes staged mail only; the journal keeps the event.
    - So `backgroundReportCount(in:of:)` must find the report by the envelope's own token, not by `correlationID == token`.
    - Plan: take the execute run's token from the probe (`ShellRunContextProbe`, the shell run's own context), replace the `pendingEnvelope` check with a check that an execute run started under a token, count the report by envelope token, update doc comments. Model-free test in IntegrationTests (precedent: Web/BlockedProviderRuleTests).
  timestamp: 2026-10-09T13:08:09.340404+00:00
- actor: claude-code
  id: 01m4gd1grh8k677her6khe3vv4
  text: |-
    ### implement — changed
    - What changed: the scenario takes the execute run's token from the run's own context (`ShellRunPlaneObservation.executeRunToken`, from `ShellRunContextProbe`). The `pendingEnvelope` check is now `executeRunStarted`. `backgroundReportCount(in:of:)` counts a progress event by the token of its envelope (`PendingRunEnvelope.makeDecoded`) and not by `correlationID`, because the inner execute run's report stands under the OUTER runCode correlation. Removed `backgroundRunToken(in:)` (read the outer tool outputs). Doc comments in ShellBackgroundRunner.swift and ShellBackgroundTests.swift now state the settle-period rule.
    - TDD: new model-free suite ShellBackgroundReportTests (2 tests). RED: report under the outer correlation counted 0. GREEN after the fix.
    - Live: `swift test --package-path IntegrationTests --no-parallel --filter ShellBackgroundTests` passed, 1 test, 40.8 s. SCENARIO result=PASS, all 7 checks pass, executeToken=01M4GCV9QW80X5S3JHF7XCX84T backgroundReports=1 cancel=stopped childGone=true sweptTerminals=1.
    - Root: `swift build --build-tests` complete; `swift test` 2339 tests in 206 suites passed. The only warning is the SwiftPM "missing creator for mutated node ... mlx-swift_Cmlx.bundle" build-system line, which comes from no source file.
    - Files: IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ShellBackgroundRunner.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellBackgroundTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellBackgroundReportTests.swift (new).
    - next: /review
  timestamp: 2026-10-09T13:18:34.769127+00:00
position_column: doing
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
- [x] The scenario finds the background run of the shell command without an outer pending envelope.
- [x] Every other check of the scenario (live read, stop, child gone, journal, sweep) still holds.
- [x] No check depends on a fixed model wording or a fixed model score.

## Tests
- [x] Run the scenario live in IntegrationTests (`swift test --filter <the shell background suite>`) and see it pass.
- [x] Root `swift test` passes.

## Workflow
- Use `/tdd` where a model-free check can show the failure first.