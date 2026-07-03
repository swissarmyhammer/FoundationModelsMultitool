---
comments:
- actor: wballard
  id: 01kwm2c68hd5rc7993t7v83s8n
  text: |-
    Implementation complete, verification in progress.

    SDK pin resolution: `Evaluations.framework` DOES exist in the shipping macOS 27 SDK (`/Applications/Xcode-beta.app/.../MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework`). Inspected its `.swiftinterface` directly (not guessed) to get the real API shape. It's a system framework — no Package.swift changes needed, `import Evaluations` just works, same as `FoundationModels`/`Testing`/`TabularData`.

    Deviations from plan.md's guessed API, found and documented in code:
    - `Metric.score(_:)` guess → actual is `Metric.scoring(_:rationale:)`.
    - `ModelSample.expectations: TrajectoryExpectation?` is scoped to Apple's own `FoundationModels.Transcript.ToolCall` recording (via `Evaluations.ToolCallEvaluator`/`StructuredTranscript`) — doesn't apply since `MultiToolAgent` never produces an Apple `Transcript` (it drives its own loop over a Router `RoutedSession`). So scenario expectations (expectFindAPIs/expectedToolPaths/maxRunCodeStepsBeforeFinal) live on a custom `AgentSubject`/`AgentScenarioExpectation` instead, graded against the real Router JSONL transcript via the existing `TranscriptAnalyzer`.
    - The library's closure-based `Evaluator<Input>` convenience hard-codes `Subject == ModelSubject<Input.ExpectedValue>`, incompatible with a custom `Subject` — so evaluators are direct `EvaluatorProtocol` conformances instead.
    - `SampleGenerator.makeSamples`/`ModelJudgeEvaluator` are real and available but deliberately unused (both explicitly optional in the plan); documented why in `AgentEvaluation.swift`'s doc comment.

    What was built:
    - `Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift` — reusable `EvaluatorProtocol` conformers + `AgentSubject`/`AgentScenarioExpectation`, shared by both the gated and ungated suites (no duplicated grading logic).
    - `Tests/FoundationModelsMultitoolIntegrationTests/AgentEvaluation.swift` — gated `Evaluation` conformer whose `subject(from:)` runs `MultiToolAgent.respond(to:)` live per M6.5a scenario (reuses `Fixtures/ScenarioTools.swift`), resolving+tearing down a fresh `LiveRouterFixture` per scenario (mirrors `ScenarioRunner`'s precedent, avoiding transcript bleed across samples). `.enabled(if: multitoolIntegrationEnabled)` gates it.
    - `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` — ungated. Unit-tests each evaluator against the existing M6.5a fixture JSONL, plus a fully offline `FixtureGateEvaluation` that runs the REAL `Evaluations.Evaluation.run()`/`aggregateValue(.mean(of:))` pipeline against fixture-derived subjects, proving the actual threshold-gate machinery flips false→true across the 0.9 threshold (all-failing/all-passing/mixed datasets) — not just our own arithmetic.

    Verification (fresh, this session): `swift build` → exit 0, only a pre-existing unrelated warning (mlx-swift Cmlx bundle, present before this task). `swift test` → main target 222/222 passing (was 213 before this task, +9 new EvaluatorGateTests), integration target 10/10 reported "skipped" in 0.001s (includes the new gated AgentEvaluation suite) — zero downloads, zero live inference, confirming the ungated acceptance criteria. Did NOT set MULTITOOL_INTEGRATION=1 per the task's explicit safety scoping.

    Adversarial double-check agent dispatched for a second pass; will report its verdict next.
  timestamp: 2026-07-03T13:23:33.265185+00:00
- actor: wballard
  id: 01kwm2mrh3tfr9w3tzzg91he3p
  text: |-
    Adversarial double-check: REVISE with one low-severity finding — `AgentEvaluation.swift`'s top-level `scenarios` doc comment claimed the four M6.5a scenarios were reused "verbatim," which contradicted the very next comment explaining scenario 3's prompt is deliberately reworded (to keep every scenario's prompt text unique, since `subject(from:)` looks a scenario up by prompt). Fixed by softening the top-level claim to "tools and expectations are verbatim; scenario 3's prompt is deliberately reworded (see its own comment below)."

    The reviewer also independently verified (by reading the M6.5a source) that this reword was in fact load-bearing and correct: `SearchThenCallTests.swift`'s `composeChain` and `discoveryUnderDistractors` scenarios share the identical prompt "Of the cities on my trip, which is warmest right now?" — had this eval reused that prompt verbatim for both, `subject(from:)`'s `.first(where:)` lookup would have collided, silently running the ~20-distractor scenario against the 2-tool compose/chain set.

    Re-ran `swift build` + `swift test` fresh after the fix: build clean (only the pre-existing, unrelated `mlx-swift_Cmlx.bundle` warning), main target 222/222 passing, integration target 10/10 reported skipped in 0.001s with `MULTITOOL_INTEGRATION` unset.

    Task is green and ready for /review. Leaving in `doing` per the implement workflow — not moving to review myself.
  timestamp: 2026-07-03T13:28:14.115067+00:00
depends_on:
- 01KWFNXEWE0EYWYQVS6M70R7K9
position_column: doing
position_ordinal: '80'
title: 'M6.5b: Evaluations-framework eval suite grading search-then-call'
---
## What
Per plan.md M6.5 "Apple's Evaluations framework": score the agent as an eval, not string-equality tests. Lives in the gated integration target (same env var).
- `Tests/FoundationModelsMultitoolIntegrationTests/AgentEvaluation.swift` — `import Evaluations`; an `Evaluation` conformer whose subject runs `MultiToolAgent.respond(to:)` end to end per sample.
- Dataset: `ArrayLoader(samples: [ModelSample(prompt:expected:)])` built from the four M6.5a scenarios; optionally widen with `SampleGenerator.makeSamples(…, targetCount:)` paraphrase/distractor variants.
- Deterministic evaluators over the recorded loop/transcript: `Metric("SearchedThenCalled")`, `Metric("CalledExpectedTools")`, `Metric("RepairedWithinN")` — each `passing(rationale:)`/`failing(rationale:)`; aggregate via `aggregateMetrics(using:)` (`computeMean`, `computeStandardDeviation`).
- Optional `ModelJudgeEvaluator` with a `.numeric` scale / `ScoreDimension` for final-answer quality (judge model is pure test infra, orthogonal to Router running the feature).
- Gate: `@Test(.evaluates(evaluation, info:))` + `#expect(EvaluationContext.current.result.aggregateValue(.mean(of: searchedThenCalled)) >= 0.9)` (thresholds tunable per metric).
- **Pin:** confirm exact `Evaluation`-conformance member names / `.evaluates` signature against the shipping OS-27 SDK (framework + types verified from WWDC26 #298; member names may differ by seed) — resolve at implementation and adjust.

## Acceptance Criteria
- [x] The eval suite compiles against the shipping Evaluations SDK (pin resolved; deviations documented in code docs)
- [x] Ungated: suite skips cleanly like M6.5a
- [x] The evaluator + threshold-gate logic is proven by a persistent ungated unit test: fixture metric values below the threshold make the gate expression evaluate false, above make it true (extends the fixture-transcript evaluator tests — no one-time manual inversion ritual)
- [ ] *(gated — verifiable when Router live inference lands)* A gated run produces per-sample results + aggregate means for all three metrics in the Swift Testing report; closing this task requires the ungated criteria only — **implemented but NOT executed in this sandbox**, per the task's explicit safety scoping (no `MULTITOOL_INTEGRATION=1`, no live model/network). `AgentEvaluation.swift` is structurally complete and compiles; needs a real run on capable hardware with a live Router to close out.

## Tests
- [ ] The eval suite IS the gated test: `MULTITOOL_INTEGRATION=1 swift test --filter AgentEvaluation` → passes on capable hardware with live Router — **not executed**, same reason as above.
- [x] `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` — ungated: metric evaluators + threshold gate against fixture transcripts/values (reuses M6.5a's parser fixtures)
- [x] `swift test --filter EvaluatorGateTests` → passes in normal CI (9/9)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## SDK pin resolution (found during implementation)

`Evaluations.framework` DOES ship in the shipping macOS 27 SDK (found under `.../MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework`; inspected its `.swiftinterface` directly rather than guessing). It's a system framework — no `Package.swift` changes were needed to `import Evaluations`, same as `FoundationModels`/`Testing`/`TabularData`.

Deviations from plan.md's guessed API, resolved and documented in code (`AgentEvaluation.swift`'s doc comment, `AgentEvaluators.swift`'s doc comments):
- `Metric.score(_:)` (plan.md's guess) → actual is `Metric.scoring(_:rationale:)`; unused here since every metric is deterministic pass/fail/ignore.
- `ModelSample.expectations: TrajectoryExpectation?` is scoped to Apple's own `FoundationModels.Transcript.ToolCall` recording (via `Evaluations.ToolCallEvaluator`/`StructuredTranscript`) — doesn't apply, since `MultiToolAgent` never produces an Apple `Transcript` (it drives its own loop over a Router `RoutedSession`). Scenario expectations instead travel on a custom `AgentSubject`/`AgentScenarioExpectation`, graded against the real Router JSONL transcript via the existing `TranscriptAnalyzer`.
- The library's closure-based `Evaluator<Input>` convenience hard-codes `Subject == ModelSubject<Input.ExpectedValue>`, incompatible with the custom `Subject` this needs — evaluators are direct `EvaluatorProtocol` conformances instead.
- `SampleGenerator.makeSamples`/`ModelJudgeEvaluator` are real and available but deliberately unused — both explicitly optional in the plan; reasoning documented in `AgentEvaluation.swift`.

## What was built
- `Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift` — `AgentMetricName`, `AgentScenarioExpectation`, `AgentSubject: EvaluationSubject`, and three `EvaluatorProtocol` conformers (`SearchedThenCalledEvaluator`, `CalledExpectedToolsEvaluator`, `RepairedWithinNEvaluator`), shared by both the gated and ungated suites (no duplicated grading logic).
- `Tests/FoundationModelsMultitoolIntegrationTests/AgentEvaluation.swift` — the gated `Evaluation` conformer; `subject(from:)` resolves a fresh `LiveRouterFixture` per scenario (mirroring `ScenarioRunner`'s M6.5a precedent, avoiding transcript bleed across samples) and runs `MultiToolAgent.respond(to:)` live against each of the four M6.5a scenarios (reusing `Fixtures/ScenarioTools.swift`). Gated via `.enabled(if: multitoolIntegrationEnabled)`.
- `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` — ungated. Unit-tests each evaluator against the existing M6.5a fixture JSONL (`Goldens/SearchThenCallTranscript.jsonl`, `Goldens/RepairTranscript.jsonl`), plus a fully offline `FixtureGateEvaluation` that calls the *real* `Evaluations.Evaluation.run()`/`EvaluationResult.aggregateValue(.mean(of:))` pipeline against fixture-derived subjects, proving the actual threshold-gate machinery flips false→true across a 0.9 threshold for all-failing/all-passing/mixed datasets.

## Verification
Fresh `swift build` + `swift test`: build clean (only a pre-existing, unrelated `mlx-swift_Cmlx.bundle` warning present before this task); main target 222/222 passing (was 213 before this task, +9 new `EvaluatorGateTests`); integration target 10/10 reported "skipped" in 0.001s with `MULTITOOL_INTEGRATION` unset (zero downloads, zero live inference). Adversarial double-check ran once, found one low-severity doc-comment self-contradiction in `AgentEvaluation.swift` (fixed), otherwise confirmed correctness of the scenario-prompt-uniqueness fix, the threshold-gate arithmetic, and the path-traversal-safe fixture loader.