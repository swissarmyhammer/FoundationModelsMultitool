---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0fny00dngjcha7sy2z4gc0y
  text: |-
    Picked up after the blocker cleared. Verification and work done in TDD order:

    1. Verified the shared workflow. Fetched swissarmyhammer/workflows; origin/main is 0580114. Read the landed swift-ci.yaml whole. It matches the card: `integration-package-path` opts the integration job in, the unit job builds the nested package on every run, the metallib glob searches `<dir>/.build` and copies the file beside each `.xctest` bundle, the integration job declares `needs: test`, and `integration-gate-env` combined with the package path stops the job.
    2. RED. Rewrote `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` to four tests: the `uses:` line points at the shared swift-ci.yaml at main, the call passes `integration-package-path: IntegrationTests`, the call passes `integration-no-parallel: true`, and the call passes a non-empty `integration-metallib-glob`. Dropped the `needs: unit` assertion — the shared workflow owns that edge now. Ran `swift test --filter CIWorkflowTests` against the old repo-local ci.yml: all 4 tests failed, each for the missing shared call. Deleted the now-unused `jobBlock`/`endsJobBlock` helpers and the `CIWorkflowTestsError` type.
    3. GREEN. Rewrote `.github/workflows/ci.yml` to one `ci` job that calls the shared workflow with the three inputs (metallib glob `*Cmlx*/default.metallib`, as the old shared call used). Removed the repo-local unit and integration jobs. Replaced the header comment: it now says why the workflow delegates, names workflows commit 0580114, and keeps the structural-split rule. Kept `concurrency` and the trigger block. `swift test --filter CIWorkflowTests`: 4 of 4 pass.
    4. Full runs. Root `swift test`: 367 tests in 32 suites, all pass, zero skipped. `swift build --package-path IntegrationTests --build-tests`: clean. The one build note, "missing creator for mutated node" for the mlx-swift Cmlx bundle, is a pre-existing SwiftPM message and shows on unchanged trees too.

    Open items: the green-CI-run acceptance box and the job-order box stay open. They need a push to main and a look at the run.
  timestamp: 2026-08-20T13:31:54.765911+00:00
- actor: claude-code
  id: 01m0fny5damay7ejnpvnpwszdt
  text: |-
    ### implement — changed
    - evidence: 2 files — .github/workflows/ci.yml, Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift. Red first: 4 of 4 rewritten tests failed against the old repo-local ci.yml. Green: `swift test --filter CIWorkflowTests` 4 of 4 pass; root `swift test` 367 tests in 32 suites, zero failures, zero skipped; `swift build --package-path IntegrationTests --build-tests` clean.
    - next: push to main, record the green run id and the job times on the card, then check the two open acceptance boxes.
  timestamp: 2026-08-20T13:32:00.298693+00:00
- actor: claude-code
  id: 01m0fpc10fbk13xp7fya701ysp
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit c67385b) — 0 findings. The engine examined `.github/workflows/ci.yml` and `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`. An ignore rule excluded 6 `.kanban/` files.
    - next: push the commit and record the green CI run id and job times on this card. The two open acceptance boxes wait for that run and do not block the review gate.
  timestamp: 2026-08-20T13:39:34.543454+00:00
- actor: claude-code
  id: 01m0fpcmf8vn5qfjwqbqgtfjm0
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — ci.yml delegates to shared swift-ci (0580114 interface); CIWorkflowTests re-pinned, red-first
    - test: green — root swift test 367/32, 0 skipped; IntegrationTests --build-tests clean
    - commit: c67385b
    - review: clean — 0 findings; task moved to done. The green-CI boxes wait on the push.
  timestamp: 2026-08-20T13:39:54.472122+00:00
position_column: done
position_ordinal: d980
title: Call the shared swift-ci.yaml for unit and integration, replacing the repo-local jobs
---
Will's directive 2026-08-21: every repo uses the shared CI (swissarmyhammer/workflows swift-ci.yaml) for a unified approach. This repo went repo-local on `^dwzkfzx` because the shared workflow then had no way to run a nested integration package. The workflows session is adding an `integration-package-path` input now (requested 2026-08-21); this card converts our ci.yml once that lands.

BLOCKER CLEARED 2026-08-20: workflows origin/main is 0580114 — "feat(swift-ci): run a nested integration package with integration-package-path". Verified by fetch and by a read of the landed file: the shared swift-ci.yaml accepts `integration-package-path`, its unit job builds the nested package on every run when that input is set, its integration job declares `needs: test`, and the metallib copy searches `<dir>/.build`.

## What

- Rewrite `.github/workflows/ci.yml` to one `uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main` call with: the nested-package input set to `IntegrationTests`, `integration-no-parallel: true`, and the metallib glob input. Remove the repo-local unit and integration jobs.
- Keep the behavior the repo-local jobs guaranteed, now via the shared workflow: every-run build of the integration package, metallib colocated beside the `.xctest`, `--no-parallel`, and integration ordered after unit (`needs: test` inside the shared workflow).
- Rewrite `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`: it currently pins `needs: unit` in the repo-local file, which the conversion deletes. It must instead pin the new invariants readable from our ci.yml: the `uses:` line points at the shared swift-ci.yaml, the nested-package input names `IntegrationTests`, and `integration-no-parallel` is true. The ordering guarantee moves into the shared workflow, so our test pins that we delegate, not the edge itself.
- Update the ci.yml header comment: it currently documents why the workflow is repo-local; that reason ends when the shared workflow supports the nested shape.

## Acceptance Criteria

- [x] `.github/workflows/ci.yml` calls the shared swift-ci.yaml and declares no repo-local test jobs
- [x] `CIWorkflowTests` pins the shared call and its inputs, and fails when the nested-package input or `--no-parallel` is dropped
- [ ] A green CI run on the shared workflow with both jobs executed, run id and job times recorded here
- [ ] The integration job starts only after the unit job completes on that run

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` — rewritten assertions, red before the ci.yml rewrite where feasible
- [x] `swift test` at the repo root — green, zero failures, zero skipped

## Workflow

- Use `/tdd` — rewrite the failing workflow-pinning test first, then rewrite ci.yml to make it pass.