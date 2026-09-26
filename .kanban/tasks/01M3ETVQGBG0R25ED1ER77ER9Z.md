---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fq1fb5sdn56scwfmgqmxgy
  text: 'Item moved here from task ^zhmqvxb (01M3ETTBXPEYFR2DSBAZHMQVXB): run the live check `swift test --package-path IntegrationTests --no-parallel --filter CLISmokeTests` after the IntegrationTests package compiles again (task 01M3ETV0A0AE2F2MTGWTFHF7T4). Expected result: it passes with `CLIRunner.demoProfile`, which now has `standard = [generationModel]` ("mlx-community/Qwen3.8-27B-mxfp4") and `flash = [flashModel]` ("mlx-community/Qwen3-4B-4bit"), both resolved with the model''s own context window (`context: nil`). Also: `agentDiscoveryProfile` and `plumbingProbeProfile` in `IntegrationTests/.../Support/LiveRouterFixture.swift` still put one model in both `standard` and `flash`. With the work-queue Router, a synchronous `searchTools` on such a profile gets `SameModelDiscoveryError` / `waitInsideOpenSubmission`. Router task 01M3FP4SPYCEJ1Y6PRYZSRRNAT will make `Router.resolve` refuse such a profile.'
  timestamp: 2026-09-26T20:38:22.821676+00:00
- actor: claude-code
  id: 01m3fsc4mbac5y6wwx3m1fqv9z
  text: |-
    Research (implement, iteration 1):
    - The discovery suites (`AgentSurfaceDiscoveryTests`, `HeldOutSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests`, `OverBudgetSurfaceDiscoveryTests`, `NoDescriptionSurfaceDiscoveryTests`, `UnknownToolHintLiveTests`) call `searchTools` directly. No `standard` generation runs in them. Their graded selection tier is on `flash`. Thus the change keeps `flash` and gives `standard` a different model, as the task says: `plumbingProbeProfile` = standard `CLIRunner.flashModel` (Qwen3-4B-4bit), flash `plumbingProbeModel` (Qwen3-1.7B-4bit); `agentDiscoveryProfile` = standard `plumbingProbeModel`, flash `agentFlashModel`. The two models are already in the local cache.
    - The nested probe runs on `standard`, and Router `c208add` refuses a nested `respond` on the same model at once with `GenerationQueueError.waitInsideOpenSubmission(model:)` (`RoutedSessionActorGeneration.swift:115`, `GenerationQueue.swift:135`). The fixture tool now catches the refusal and records it with its elapsed time. The suite `.timeLimit` stays the hang detector.
    - `RespondDrainTests` measured only the old `respond(to:)` drain (condition 3 "nothing survives the call"). It is deleted with `runRespondDrainScenario`.
    - The canary now waits for the answer that mail starts, with a named deadline, and grades that answer.
    - `repetitionDetection` is not set anywhere in this package. Sessions take `RepetitionDetection()` (on, window 2,048 tokens, minimum line 20 characters). A new live suite measures a `runCode` snippet with repeated lines.
  timestamp: 2026-09-26T21:19:09.451430+00:00
- actor: claude-code
  id: 01m3fzew03fb6c2vy73z2en6sv
  text: |-
    Repetition-detection decision (live runs, 2026-09-26, profile `multitool-cli-demo`: standard `Qwen3.8-27B-mxfp4`, flash `Qwen3-4B-4bit`, Router `c208add`, direct-mode surface, `runCode` only):
    - Prompt: a `runCode` snippet with `total = total + 1; // count one more archived record` written out on N separate lines, no loop.
    - N=30: one `runCode` call, 32 snippet lines, answer "The snippet returned **30**", 101.2 s. `repetitionStops=0`, `repeatedLines` finishes 0.
    - N=200 (3 runs): time limit 10 min, 10 min, 45 min. Each run: `toolCalls=0`, reply empty, `repetitionStops=0`, `repeatedLines` finishes 0. The recording shows 1,035 and 1,782 reasoning tokens that end with "Let me write the tool call.", and then the `runCode` call did not end before the time limit. Two runs also ended with signal 11 of the test helper after the time limit cancelled the turn.
    - N=160: time limit 20 min. Same result: no tool call, no stop.
    - Decision: the log has no `repetitionStopped` event and no `FinishReason.repeatedLines`, so Multitool sessions set no `repetitionDetection` (Router default stays). The decision is recorded in the comment above `profile.standard.makeSession(tools:)` in `CLIRunner.runDemo`.
    - The permanent probe suite was not kept: with N ≥ 160 the shipped model never ends its `runCode` call, so a suite that fills one window of the watch cannot pass, and a suite with fewer lines cannot fill the window.
    - Finding for the Router board (not this repo): the 27B model generated a `runCode` call for 20-45 minutes with no `repetitionStopped` event. A tool call carries its snippet as JSON with `\n` escapes, so the watch possibly reads no line break in it. The parent session must send this to the FoundationModelsRouter peer.
  timestamp: 2026-09-26T23:05:30.371508+00:00
- actor: claude-code
  id: 01m3g2cfw2fp0nm4akca89qrdt
  text: |-
    ### implement — changed
    - evidence: `NestedGenerationProbeTests.swift`, `Fixtures/IntegrationNestedGenerationTool.swift` (refusal recorded as `NestedGenerationOutcome`, graded by `nestedGenerationChecks`: entered, refused, refused inside `integrationNestedRefusalTimeLimit` 5 s); `Support/LiveRouterFixture.swift` (`plumbingProbeProfile` standard Qwen3-4B / flash Qwen3-1.7B; `agentDiscoveryProfile` standard Qwen3-1.7B / flash Qwen3-4B); new `ProfileSlotSeparationTests.swift` (model-free); `RespondDrainTests.swift` and `runRespondDrainScenario` deleted; canary and background runners wait for the mail answer (`MailAnswerReading`); `integrationDelayedEchoDelaySeconds` 4 → 10 (a 4 s echo settled inside the 5 s inline settle grace, so no mail came), guarded in `ScenarioFixtureTests`; repetition decision in `CLIRunner.runDemo` comment.
    - Also discovered: `UnknownToolHintLiveTests` fails with the old and the new profile layout (task 01M3G1K0GGX4F743R42HD8266A).

    ### test — red
    - evidence: root `swift build --build-tests && swift test`: 1815 tests in 145 suites pass. `swift build --package-path IntegrationTests --build-tests`: pass. Live filter run (task list + CLISmokeTests + ProfileSlotSeparationTests): all pass (NestedGenerationProbeTests: refused after 0.00063 s, 10.5 s; AgentSurface 46 s; HeldOut 57 s; CLISmokeTests 2/2, 78-88 s; canary 2/2 with mail answers; OverBudget, NoDescription, RetrievalText, SelectionForkPerCall pass) except `UnknownToolHintLiveTests`. Full `swift test --package-path IntegrationTests --no-parallel`: 59 tests in 31 suites, 30 suites pass, 1 fails: `UnknownToolHintLiveTests` (2 issues: `bash.run` → `shell.grepHistory`, `terminal.runTests` → `shell.getLines`, declared `shell.execute`). Stable over 3 runs, and the same with the old profile layout, so not caused by this change. Acceptance item "full swift test passes" is stuck on that pre-existing failure.
    - next: commit, then review.
  timestamp: 2026-09-26T23:56:38.146788+00:00
depends_on:
- 01M3ETV0A0AE2F2MTGWTFHF7T4
- 01M3ETTBXPEYFR2DSBAZHMQVXB
- 01M3EVKX9JFDWDQR297Q4JRND0
- 01M3EVMDF9BZTNFR16F11CFNX0
position_column: doing
position_ordinal: '80'
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