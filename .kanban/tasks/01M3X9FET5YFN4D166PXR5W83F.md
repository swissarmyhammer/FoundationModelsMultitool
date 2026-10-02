---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3xe08p3bqg23t1qyw1cra3s
  text: |-
    Note from the implement step of `^3vtvrzg` (for this card's search for fixed model-quality assertions):
    - `OverBudgetSurfaceDiscoveryTests.swift:140` asserts `matchedPathCount > 0` over its two queries. That is a model-quality floor on `Qwen3-1.7B-4bit`. On 2026-10-01 it failed locally at HEAD (both queries answered no match), also with the `^3vtvrzg` changes stashed. CI run 36951032341 passed it with one match only, and that match was a wrong path (`deploy.download_artifact` for "read the contents of a file on disk").
    - `^3vtvrzg` renamed `agentSurfaceRoundCorrectLevel` to `agentSurfaceCorrectLevel` and `heldOutRoundCorrectLevel` to `heldOutCorrectLevel` (values unchanged), and removed the discovery rounds. `expectEveryQueryFindsACorrectPath` now takes a `DiscoveryGroupGrade`.
  timestamp: 2026-10-02T04:29:48.099220+00:00
position_column: todo
position_ordinal: '8180'
title: Replace the fixed discovery scores in the integration tests with checks that do not depend on model quality
---
## Problem

The discovery integration tests fail when a model selects one tool less than before, also when the code is correct. The user said: "Having a hard-wired 'discovery score' is going to be brittle."

Evidence: CI run 36951032341 (commit ef905bf, 2026-10-02):

- `AgentSurfaceDiscoveryTests.swift:175` asserts `round.correctCount >= agentSurfaceRoundCorrectLevel`, and `agentSurfaceRoundCorrectLevel = 19` (`AgentSurfaceDiscoveryTests.swift:98`). The run scored 18 correct and 1 wrong in each round. On 2026-09-29 it scored 19 correct and 3 wrong. Thus the selection changed: it gave fewer wrong paths, and one correct path less. The fixed level of 19 calls that a failure.
- `DiscoveryGrading.swift:145` asserts `grade.correctCount >= 1` for each query of `HeldOutSurfaceDiscoveryTests`. In each round, at least one of the 15 queries found no declared path. On 2026-09-29: 16 correct and 2 wrong; on 2026-10-02: 16 correct and 4 wrong.
- The selection changes when a model, a prompt or the ranker changes. FoundationModelsRanker changed the default selection sentence (`dbda1ae`) and the candidate format (`30b6d91`) on 2026-10-01. This is a possible cause of the change; it is not verified.

A fixed score is a measurement of model quality, and it is written as a test of the code. Thus each change of a model or a prompt can make it fail.

## Work

1. Assert only properties that the code of this package controls, and that do not depend on how well the model selects. For example:
   - each query gives an answer without an error;
   - each path in an answer is a real path of the catalog;
   - no path occurs two times in one answer;
   - the answer stays inside the selection limit.
2. Keep the correct and wrong counts in the printed `RESULT` lines, as a report. Do not assert them.
3. Remove `agentSurfaceRoundCorrectLevel` and the other fixed score levels, and the `correctCount >= 1` assertion for each query. Find every fixed level with a search (`CorrectLevel`, `correctCount >=`, `correctTotal >=`).
4. Every discovery test still runs on each push, in the same integration job. Do not move a test to a different workflow, and do not skip it.

## Acceptance criteria

- [ ] No integration test asserts a fixed number of correct discovery paths, in total or for each query.
- [ ] Each discovery test asserts the properties of item 1 of Work, and prints its correct and wrong counts.
- [ ] A test shows that a catalog path that does not exist in an answer fails the check.
- [ ] `swift build --build-tests --package-path IntegrationTests` passes, and the discovery suites pass in one real integration run (record the run id).
#ci