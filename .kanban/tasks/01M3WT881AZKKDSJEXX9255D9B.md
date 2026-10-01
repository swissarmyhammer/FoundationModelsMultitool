---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3wv145xra67fxtc01h6m058
  text: |-
    ### Fixed by the test step of ^cf57dtd
    All three failures came from upstream contract changes. No upstream defect. Each fix matches the new contract. No assertion was weakened.
    - CallSpanTests.thrownErrorSetsTheErrorStatus: FoundationModelsExtras commit 50fd4a5 makes TracedCall.run set only the error status and the error.type attribute. It records no error event. Fix: the test now expects dispatch.errors to be empty, and the error.type attribute to be the literal "FoundationModelsMultitoolTests.ThrowingToolError". The status check stays. File: Tests/FoundationModelsMultitoolTests/CallSpanTests.swift.
    - RouterDiscoverySeamsTests (selection preamble): FoundationModelsRanker commit dbda1ae gave String.selectionDefault new words. The sentence "Prefer the closest candidates over an empty answer" is gone. The default now says "Answer with an empty list only when no candidate is related to the request at all." Fix: the guard copy in the test holds the new sentence. The doc comment of makeSelection in SearchToolsTool+Seams.swift names the new sentence.
    - OverBudgetSelectionOrderTests (two tests): FoundationModelsRanker commit 30b6d91 changed the prefix format. Each candidate is now a block with "id: <id>" on its own line. The old format was "## <id>". The test helper candidateIDs read the old heading, so it found no ids, and the scripted model answered with an empty list. Fix: the helper reads the "id: " line prefix. Both tests pass.
    Evidence: swift test, 1882 tests in 154 suites, 0 failures.
  timestamp: 2026-10-01T22:58:13.309762+00:00
position_column: todo
position_ordinal: '8680'
title: Update three unit tests to the upstream changes of 2026-10-01
---
## Problem

`swift test` fails 3 tests (4 issues) after `swift package update` (2026-10-01). The cause is in the upstream packages, not in this package. Task `^cf57dtd` found these failures and did not change them, because they are outside its scope.

## Evidence

- `CallSpanTests.thrownErrorSetsTheErrorStatus` (CallSpanTests.swift, `#expect(dispatch.errors.count == 1)`): the count is 0. FoundationModelsExtras commit `50fd4a5` ("fix(telemetry)!: record only the error type on the span of TracedCall.run, never the error description") removed the error event. `TracedCall.recordFailure` now sets only the error status and the `errorType` attribute.
- `RouterDiscoverySeamsTests` ("the selection tier is seeded with a preamble that tells the model to prefer the closest candidates over an empty answer"): `config.preamble` does not contain "Prefer the closest candidates over an empty answer; answer with an empty list only when no candidate is related to the task at all." No checkout contains that sentence now.
- `OverBudgetSelectionOrderTests` (two tests): `recorder.slices` is empty, and the merged answer has 0 catalog paths. The selection tier of FoundationModelsMetadataRegistry (checkout `91d4225`) does not call the recorder as the test expects.

## Work

- [ ] Find the upstream change for each failure, and record it with its commit.
- [ ] Change each test (or the code of this package) to the new upstream contract. Do not weaken an assertion without a reason that the upstream change gives.
- [ ] `swift test` passes.
#defect