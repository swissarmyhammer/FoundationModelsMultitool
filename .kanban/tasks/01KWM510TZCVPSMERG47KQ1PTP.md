---
position_column: todo
position_ordinal: '9280'
title: 'AgentEvaluators.swift: RepairedWithinNEvaluator passing rationale text overclaims .final was reached'
---
## What
Discovered while fixing doc-comment accuracy on `RepairedWithinNEvaluator.metrics(subject:input:)` (`Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift`).

`TranscriptAnalyzer.runCodeStepsBeforeFinal(in:)` (`Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift`) returns the count of `.runCode` steps before the first `.final` step — but if `subject.steps` never contains a `.final` step at all, it falls through and returns the *total* `.runCode` count instead.

`RepairedWithinNEvaluator.metrics` only checks `attempts <= bound` and, when true, emits:
```swift
metric.passing(rationale: "reached final within \(attempts) of \(bound) allowed runCode attempt(s).")
```
This rationale text asserts `.final` was reached even when it wasn't (e.g. a run that terminates without ever producing a `.final` step, but whose `.runCode` count happens to be `<= bound`). This is a pre-existing behavior, not introduced by the doc-comment fix — the doc comments were corrected to describe the real behavior accurately, but the runtime rationale string itself still makes the same overclaim.

Not fixed as part of the doc-comment task (M6.5b review round 3) because it's a behavior-adjacent code/string change, out of that task's scope.

## Acceptance Criteria
- [ ] Decide and resolve: either (a) reword the passing rationale to not claim `.final` was reached (e.g. "used N of M allowed runCode attempt(s) before reaching .final or exhausting steps."), or (b) if the intended contract is that `.final` truly must be reached, add that check to the evaluator (`subject.steps.contains(where: \.isFinal)` or similar) so a run that never reaches `.final` cannot pass.
- [ ] Add/extend an `EvaluatorGateTests` case covering a fixture transcript with `.runCode` steps but no `.final` step, at or under the bound — pin down which behavior is intended.

## Tests
- [ ] `swift test --filter EvaluatorGateTests` passes with the new case