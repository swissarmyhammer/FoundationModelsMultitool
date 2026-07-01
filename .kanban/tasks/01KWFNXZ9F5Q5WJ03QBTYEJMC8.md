---
depends_on:
- 01KWFNXEWE0EYWYQVS6M70R7K9
position_column: todo
position_ordinal: 8c80
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
- [ ] The eval suite compiles against the shipping Evaluations SDK (pin resolved; deviations documented in code docs)
- [ ] Ungated: suite skips cleanly like M6.5a
- [ ] The evaluator + threshold-gate logic is proven by a persistent ungated unit test: fixture metric values below the threshold make the gate expression evaluate false, above make it true (extends the fixture-transcript evaluator tests — no one-time manual inversion ritual)
- [ ] *(gated — verifiable when Router live inference lands)* A gated run produces per-sample results + aggregate means for all three metrics in the Swift Testing report; closing this task requires the ungated criteria only

## Tests
- [ ] The eval suite IS the gated test: `MULTITOOL_INTEGRATION=1 swift test --filter AgentEvaluation` → passes on capable hardware with live Router
- [ ] `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` — ungated: metric evaluators + threshold gate against fixture transcripts/values (reuses M6.5a's parser fixtures)
- [ ] `swift test --filter EvaluatorGateTests` → passes in normal CI

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.