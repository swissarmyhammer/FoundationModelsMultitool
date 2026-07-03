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
- actor: wballard
  id: 01kwn03b5kty3fyh1swqz2r2wf
  text: |-
    Pulled back from review into doing to address review-findings checklist item. Re-read the file to confirm current location (line 181, not 206 — shifted since the finding was recorded). Confirmed the finding: `?? true` would make `#expect(!(... ?? true))` fail on a nil rationale, which contradicts the test's own stated intent ("must not claim .final was reached" — vacuously true if there's no rationale text at all).

    Changed line 181 in Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift:
    `#expect(!(metrics.first?.rationale?.contains("final") ?? true), ...)` -> `?? false`

    Verified: `swift build` exit 0; `swift test --filter FoundationModelsMultitoolTests` -> 247/247 passed; `swift test --filter EvaluatorGateTests` -> 10/10 passed (including the target test `repairedWithinNPassesWithoutReachingFinal`).

    Marked the review-findings checklist item [x] in the task description. Spawned double-check agent for adversarial sign-off per really-done; awaiting verdict before finalizing. Leaving task in doing per /implement process.
  timestamp: 2026-07-03T22:03:00.659442+00:00
- actor: wballard
  id: 01kwn064ehw037099n4c6t7neh
  text: |-
    double-check adversarial review: PASS, no findings. Independently confirmed via git diff that only the one line in EvaluatorGateTests.swift changed (plus kanban bookkeeping); walked all three cases of the `?? false` fallback (nil rationale -> vacuous pass; non-nil containing "final" -> fails; non-nil not containing "final" -> passes) and confirmed correctness; ran a fresh `swift build` (exit 0) and `swift test --filter EvaluatorGateTests` (10/10 passed) independently.

    Noted for the record: `RepairedWithinNEvaluator.metrics`'s rationale is always non-nil in current production code (both passing/failing branches interpolate a string), so this fix has no observable production-behavior effect today — it's a correctness-of-intent fix for the test's own vacuous-truth semantics on a nil rationale, guarding against future evaluator changes that could return a nil rationale.

    Full suite re-confirmed green: swift build exit 0; swift test --filter FoundationModelsMultitoolTests -> 247/247 passed. Review-findings checklist item marked [x]. Leaving task in doing for /review.
  timestamp: 2026-07-03T22:04:32.081799+00:00
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

## Review Findings (2026-07-03 16:55)

- [x] `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift:206` — The default value `true` in `?? true` causes the test to fail if `rationale` is nil. Since optional chaining on a nil rationale returns nil, the coalescing operator defaults to true, then negation produces false, failing the expectation. The test comment says 'the passing rationale must not claim .final was reached', which should pass whether rationale exists or not—the constraint is only that IF it exists, it must not contain 'final'. The correct default should be `false` to allow nil rationale. Change `?? true` to `?? false`: `#expect(!(metrics.first?.rationale?.contains("final") ?? false), ...)`.
