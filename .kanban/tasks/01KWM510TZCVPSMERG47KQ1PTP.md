---
comments:
- actor: wballard
  id: 01kwm5kkf19yysf60e5h2s6zby
  text: |-
    Partial overlap with parent task `tyejmc8` (M6.5b), not full redundancy.

    The official /review gate for `tyejmc8` confirmed this exact rationale-string overclaim as an in-scope finding directly on that task's own diff (round 4, 2026-07-03 09:13), so it was fixed there rather than deferred again: `RepairedWithinNEvaluator.metrics(subject:input:)`'s passing rationale in `Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift` now reads `"used \(attempts) of \(bound) allowed runCode attempt(s)."` — dropping the "reached final" claim, per this task's AC1 option (a) (reword rather than add a hard `.final`-reached requirement to the evaluator).

    That resolves AC1 here. **AC2 is still open**: an `EvaluatorGateTests` case covering a fixture transcript with `.runCode` steps but no `.final` step, at or under the bound, to pin down/lock in the chosen behavior (that such a run legitimately passes without claiming `.final` was reached) does not exist yet — I checked `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` and found no such fixture/case. This task should stay open for that remaining test coverage; not closing it myself, leaving that call to the board owner.
  timestamp: 2026-07-03T14:20:01.889537+00:00
- actor: wballard
  id: 01kwmz620gegjxq8zaz6vwb7vc
  text: |-
    AC2 implemented via TDD. Added `repairedWithinNPassesWithoutReachingFinal()` to `EvaluatorGateTests.swift`: a synthetic `[.findAPIs, .runCode]` steps array (no `.final`), `maxRunCodeStepsBeforeFinal: 1`. Asserts the metric is `.passing` and that `rationale` does not contain "final".

    RED-GREEN-RED verified manually: temporarily reverted `RepairedWithinNEvaluator`'s passing rationale in `AgentEvaluators.swift` back to the old overclaiming `"reached final within N of M allowed runCode attempt(s)."` string, reran `swift test --filter EvaluatorGateTests` — the new test failed with exactly the expected assertion (`!(metrics.first?.rationale?.contains("final") ?? true)` → false), all 9 other cases in the suite still passed. Restored the fix (`git diff --stat` on the source file came back empty, confirming a no-op restore), reran — green again.

    Full suite: `swift build` exit 0; `swift test --filter FoundationModelsMultitoolTests` → 247/247 passed (was 246 before this task's new test).

    Spawned `double-check` agent for adversarial sign-off per really-done; awaiting its verdict before considering this fully done.
  timestamp: 2026-07-03T21:47:01.008376+00:00
- actor: wballard
  id: 01kwmzcngr4kdas8xwzftjdypg
  text: |-
    double-check adversarial review: PASS, no findings. Independently re-verified (fresh swift build --build-tests + swift test --filter EvaluatorGateTests, 10/10) that the synthetic [.findAPIs, .runCode] steps array (no .final) drives TranscriptAnalyzer.runCodeStepsBeforeFinal(in:) to its fall-through path returning count 1, which is <= maxRunCodeStepsBeforeFinal: 1, so RepairedWithinNEvaluator grades .passing; confirmed the rationale-regression assertion would genuinely trip against the old overclaiming wording; confirmed via git diff --name-only that only EvaluatorGateTests.swift (+22/-0) plus kanban bookkeeping changed — no production code touched.

    Final fresh full-suite run: swift build exit 0; swift test --filter FoundationModelsMultitoolTests → 247/247 passed.

    Both acceptance criteria closed (AC1 was already done pre-task per prior comment; AC2 done here). Leaving task in doing for /review.
  timestamp: 2026-07-03T21:50:37.592521+00:00
position_column: doing
position_ordinal: '80'
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