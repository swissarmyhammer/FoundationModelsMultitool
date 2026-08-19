---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0dq6znfbnhe4fdrbwq9cb4c
  text: 'Picked up. Read the full validator rule set for .swift and .yml. Plan, in TDD order: (1) write Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift, which reads .github/workflows/ci.yml from disk through #filePath (the same shape as HardeningTests.readmeInjectedGlobals) and asserts that the integration job declares "needs: unit"; (2) run the test and see it fail; (3) add "needs: unit" with a reason comment to the integration job, with no change to any step; (4) run the test and see it pass; (5) run the full root "swift test".'
  timestamp: 2026-08-19T19:15:49.039719+00:00
- actor: claude-code
  id: 01m0dqa5gsr4y3qmm88brnvxgk
  text: |-
    Implementation done, in TDD order.

    1. RED: wrote Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift. It reads .github/workflows/ci.yml through #filePath (the same shape as HardeningTests.readmeInjectedGlobals) and asserts that the integration job block holds a "needs: unit" line. Ran "swift test --filter CIWorkflowTests" before the workflow edit: 1 test, 1 failure, with the expected message — the workflow had no "needs: unit".
    2. GREEN: added "needs: unit" to the integration job in .github/workflows/ci.yml, with a comment that states the reason: one runner label, fail-fast order, run 32285751680 as the measurement. No step of either job changed — only the comment and the "needs: unit" line were inserted. Ran the filtered test again: 1 test, passed.
    3. Full root "swift test": 362 tests in 31 suites, all passed, zero failures, zero skipped, zero warnings. A search of the full run output found no "skip", "warning", "known issue", or "missing creator" line.

    The last acceptance-criteria box stays open: the CI-run-order proof needs a push, and this card gets the run id from "gh run view <id> --json jobs" after that push.

    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift (new), .github/workflows/ci.yml (needs: unit + reason comment). Test failed before the workflow edit, passed after it. Full swift test: 362 tests in 31 suites, 0 failures, 0 skipped.
    - next: /review; after the next push, record the CI run id that shows the job order.
  timestamp: 2026-08-19T19:17:33.337687+00:00
position_column: doing
position_ordinal: '8380'
title: 'CI: run the integration job only after the unit job passes'
---
Observed on CI run `32285751680` (push `dad8ba8`, 2026-08-19): the job "Integration (real models, real GPU)" started at 18:09:39 and held the runner for more than an hour, while the job "Unit tests" stayed queued behind it. Both jobs in `.github/workflows/ci.yml` target the same `[self-hosted, macOS]` label, and no `needs:` edge orders them — so GitHub assigns the runner in arbitrary order, and the ~70-minute job can run first. The fast fail signal then comes last. This is the opposite of fail-fast.

Separate context, not this card's work: the red on run `32203706380` is the old canary's 600-second ceiling. Commits `cf55b56` and `cda247d` (task `^nhxj8hx`) already correct that; a push carries them.

## What

- Edit `.github/workflows/ci.yml`: add `needs: unit` to the `integration` job. Effect: the integration job starts only after the unit job succeeds, so a compile error or a unit failure reports in minutes and no 70-minute run starts on a broken tree.
- Keep every existing step of both jobs unchanged — the clean steps, the integration-package build in the unit job (the compile coupling), the metallib copy, and `--no-parallel`.
- Add a comment above `needs:` that states the reason: one runner label, fail-fast order, run `32285751680` as the measurement.
- Add `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`: a unit test that reads `.github/workflows/ci.yml` off disk via `#filePath` (the same shape `HardeningTests.readmeInjectedGlobals()` uses at `HardeningTests.swift:360`) and asserts the `integration:` job declares `needs: unit`. This pins the shipped configuration so a later edit cannot drop the edge without a red unit test.

## Acceptance Criteria

- [x] The `integration` job in `.github/workflows/ci.yml` declares `needs: unit`
- [x] All existing steps of both jobs are unchanged
- [x] `CIWorkflowTests` fails when `needs: unit` is removed, and passes with it present
- [ ] On the next CI run, the integration job starts only after the unit job completes (recorded here with the run id, from `gh run view <id> --json jobs`)

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` — new test asserting the workflow's `integration` job carries `needs: unit`
- [x] `swift test` at the repo root — green, zero failures, zero skipped

## Workflow

- Use `/tdd` — write the failing workflow-pinning test first, then edit the workflow to make it pass.