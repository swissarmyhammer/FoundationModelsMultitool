---
assignees:
- claude-code
depends_on:
- 01M3ETV0A0AE2F2MTGWTFHF7T4
- 01M3ETTBXPEYFR2DSBAZHMQVXB
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
position_column: todo
position_ordinal: '8480'
title: 'Change the live suites for the same-model refusal: assert the refusal and split the single-model profiles'
---
## What
Before, a nested `respond` on the same model from inside a tool call deadlocked silently. `NestedGenerationProbeTests.swift:1-30` documents the old `generationGate` hang. With the new Router it is refused at once with `GenerationQueueError.waitInsideOpenSubmission(model:)`. Also, `respond(to:)` no longer drains background runs: they come back as mail. Change the live suites under `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/` to match:

- [ ] `NestedGenerationProbeTests.swift` and `Fixtures/IntegrationNestedGenerationTool.swift:111`: assert that the in-band nested call gets `waitInsideOpenSubmission` inside a short time limit and does not hang. Rewrite the doc comment, which explains the old `AsyncSemaphore` deadlock, to describe the refusal.
- [ ] `Support/LiveRouterFixture.swift`: `plumbingProbeProfile` (`:405-410`) and `agentDiscoveryProfile` (`:439-444`) put one model in both `standard` and `flash`. Give `standard` a different model in each profile whose suites run `searchTools` inside a session: `AgentSurfaceDiscoveryTests`, `HeldOutSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `OverBudgetSurfaceDiscoveryTests`, `NoDescriptionSurfaceDiscoveryTests`, `UnknownToolHintLiveTests`, and the `ScenarioRunner` plumbing runner. Write the reason in the profile doc comment. Add a model-free `@Test` in the IntegrationTests package that asserts that `standard` and `flash` do not overlap for each profile constant used by a session suite.
- [ ] Remove the dependence on the old `respond(to:)` drain: `RespondDrainTests.swift`, `InBandCollectionCanaryTests.swift`, and in `ScenarioRunner.swift` `backgroundRuns(atFirstTurnEndIn:)`, the "must self-drain" rule and `backgroundRunsAfterRespond`. Test the new contract: a background run that settles comes back as a mail submission (`SubmissionStart.cause == .mail`) and gets an answer. Delete the tests that measured only the old drain, and write the reason in the commit message.
- [ ] Repetition detection is on by default (`RepetitionDetection.defaultIsEnabled`, lines of 20 or more characters). Run one live `runCode` scenario that has repeated JavaScript lines. If the log has `repetitionStopped` or `FinishReason.repeatedLines`, set `repetitionDetection` for Multitool sessions (in `CLIRunner` and in the fixtures). Record the decision in a task comment and in the doc comment of that setting.

## Acceptance Criteria
- [ ] No profile that a session suite uses has the same model in `standard` and `flash`. The model-free test enforces this.
- [ ] The nested-generation probe fails if the nested call hangs longer than its time limit, and passes when it gets `waitInsideOpenSubmission`.
- [ ] No file under `IntegrationTests/` names `backgroundRunsAfterRespond` or `atFirstTurnEndIn`.
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes on a machine that has the models.

## Tests
- [ ] Run `swift build --package-path IntegrationTests --build-tests`. Expected result: it passes.
- [ ] Run `swift test --package-path IntegrationTests --no-parallel --filter 'NestedGenerationProbeTests|AgentSurfaceDiscoveryTests|HeldOutSurfaceDiscoveryTests|RetrievalTextSurfaceDiscoveryTests|OverBudgetSurfaceDiscoveryTests|NoDescriptionSurfaceDiscoveryTests|UnknownToolHintLiveTests|SelectionForkPerCallTests|InBandCollectionCanaryTests'`. Expected result: it passes.
- [ ] Run the full `swift test --package-path IntegrationTests --no-parallel`. Expected result: it passes.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.