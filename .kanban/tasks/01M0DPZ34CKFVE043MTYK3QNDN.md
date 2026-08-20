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
- actor: claude-code
  id: 01m0dqneg8yt2vppkfx99mkww9
  text: |-
    ### review — findings
    - evidence: 1 finding — Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:38 (reuse/reuse). Engine run: review sha HEAD~1..HEAD (commit 0ceda07). Counts: 1 finding, 1 confirmed, 0 refuted.
    - note: The open acceptance checkbox for the CI-run-order proof needs a push. It is not a review finding. It does not block the review gate.
    - next: Make one shared test utility that reads a repository file from a relative path. Use it in CIWorkflowTests and HardeningTests. Then check the finding box and run the review again.
  timestamp: 2026-08-19T19:23:42.984068+00:00
- actor: claude-code
  id: 01m0dqp0pgx026ve70mmtwfbcp
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — CIWorkflowTests.swift (new, TDD red-first) + needs: unit in ci.yml
    - test: green — root swift test 362/31, 0 skipped; IntegrationTests --build-tests clean
    - commit: 0ceda07
    - review: findings — Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:38 (extract shared repo-file reader used by HardeningTests too)
  timestamp: 2026-08-19T19:24:01.616556+00:00
- actor: claude-code
  id: 01m0dqx1rye9gjvgxgqc05acn7
  text: |-
    Correction of the review finding (reuse/reuse, CIWorkflowTests.swift:38).

    1. New file Tests/FoundationModelsMultitoolTests/RepositoryFile.swift: an internal enum with one function, RepositoryFile.read(relativePath:). It reads one repository file as UTF-8 text. Its doc comment tells that #filePath resolves relative to the file that contains the literal, so the three deletingLastPathComponent() steps go from the helper's own location to the repository root. The helper is internal, so each test file in the target can call it.
    2. CIWorkflowTests.workflowLines() now calls RepositoryFile.read(relativePath: ".github/workflows/ci.yml") and only splits the text into lines. The removed code was the four-step URL navigation.
    3. HardeningTests.readmeInjectedGlobals() now calls RepositoryFile.read(relativePath: "README.md"). The removed code was the same four-step URL navigation. No assertion changed in either test.
    4. Audit of the other #filePath sites in the unit-test target: ToolAPIRendererTests.swift:281 and BuilderSurfaceTests.swift:22. Each uses one deletingLastPathComponent() step to find the Goldens/ directory that is adjacent to the test file. They do not go to the repository root, and they read test-owned golden files, not repository files. The cause is different, so RepositoryFile.read does not apply to them, and I did not change them.
    5. Proof: root "swift test" ran two times. Each run: 362 tests in 31 suites, all passed, zero failures, zero skipped. The build shows one warning, "missing creator for mutated node" on .build/.../mlx-swift_Cmlx.bundle. I stashed this diff and built again: the same warning shows on the unchanged tree. So the warning comes from earlier .build state (the metallib copy of a gated integration run mutated the Cmlx bundle), not from this change.
    6. The finding's box is now checked. The one open acceptance box (CI run order proof) still waits for a push; it is not a review finding.

    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsMultitoolTests/RepositoryFile.swift (new), Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift, Tests/FoundationModelsMultitoolTests/HardeningTests.swift. Root swift test: 362 tests in 31 suites, 0 failures, 0 skipped, two consecutive green runs.
    - next: /review; after the next push, record the CI run id that shows the job order.
  timestamp: 2026-08-19T19:27:52.094500+00:00
- actor: claude-code
  id: 01m0dqz0yf3wq01eqdba7ajeba
  text: |-
    ### test — green
    - evidence: `swift test` — 362 tests, 31 suites, 0 failed, 0 skipped, exit 0. `swift build --package-path IntegrationTests --build-tests` — Build complete, exit 0 (only the documented third-party `missing creator for mutated node` mlx bundle warning present).
    - next: ready for review.
  timestamp: 2026-08-19T19:28:56.783631+00:00
- actor: claude-code
  id: 01m0dr56tav6xqf2cp57fecc4h
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 390e725) — 1 confirmed finding: Tests/FoundationModelsMultitoolTests/RepositoryFile.swift:25 code-security/injection
    - next: correct the finding in the new "## Review Findings (2026-08-19 14:29)" section, then run the review again. The task stays in review.
  timestamp: 2026-08-19T19:32:19.402209+00:00
- actor: claude-code
  id: 01m0dr5n7e4wt435p000ntjzwk
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — RepositoryFile.swift (new shared helper), CIWorkflowTests and HardeningTests call it
    - test: green — root swift test 362/31, 0 skipped; IntegrationTests --build-tests clean
    - commit: 390e725
    - review: findings — Tests/FoundationModelsMultitoolTests/RepositoryFile.swift:25 (validate relativePath against traversal)
  timestamp: 2026-08-19T19:32:34.158105+00:00
- actor: claude-code
  id: 01m0drcwt3q6bf37xhy3x2zmvm
  text: |-
    Correction of the review finding (code-security/injection, RepositoryFile.swift:25), in TDD order.

    1. RED: new file Tests/FoundationModelsMultitoolTests/RepositoryFileTests.swift with two tests. Each test asserts that RepositoryFile.read(relativePath:) throws RepositoryFileError — one for "../outside", one for "/etc/hosts". The tests assert the helper's own error type, not any error, because a bad path already throws a Cocoa "no such file" error today. Ran "swift test --filter RepositoryFileTests" before the guard: 2 tests, 2 failures, each with the expected message — a Cocoa error came instead of RepositoryFileError. The failure output also showed the traversal: the ".." path resolved to a location outside the repository root.
    2. GREEN: added to RepositoryFile.swift (a) the enum RepositoryFileError with one case, pathEscapesRepository(String), with a description; (b) a guard at the top of read(relativePath:) that rejects a path that contains ".." or that starts with "/", with a one-sentence comment that states why: such a path can point to a file outside the repository. The Throws doc line now names the error. Ran the filtered tests again: 2 tests, passed.
    3. Full root "swift test": 364 tests in 32 suites, all passed, zero failures, zero skipped. A search of the full run output found no "fail", "skip", "warning", "known issue", or "missing creator" line.
    4. The finding's box is now checked. The one open acceptance box (CI run order proof) still waits for a push; it is not a review finding.
    5. Side note: the description's spelling of the filePath literal lost its hash prefix in this update, so the kanban tag parser cannot read it as a tag.

    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsMultitoolTests/RepositoryFile.swift (guard + RepositoryFileError), Tests/FoundationModelsMultitoolTests/RepositoryFileTests.swift (new, 2 tests, red-first). Root swift test: 364 tests in 32 suites, 0 failures, 0 skipped.
    - next: /review; after the next push, record the CI run id that shows the job order.
  timestamp: 2026-08-19T19:36:31.299697+00:00
- actor: claude-code
  id: 01m0drjhjj0q7wck953wvy178v
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit b0917c5, the path-traversal guard and its tests) — 0 findings; counts: findings 0, confirmed 0, refuted 0. All items in the two prior "## Review Findings" sections have a check.
    - next: push the branch, then record the CI run id for the open acceptance item (the run-order proof). That item is not a review finding and did not block this gate. Task moved to done.
  timestamp: 2026-08-19T19:39:36.402693+00:00
- actor: claude-code
  id: 01m0drk3n5052bjqdcdp6qf72f
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — RepositoryFile guard (RepositoryFileError) + RepositoryFileTests, red-first
    - test: green — root swift test 364/32, 0 skipped; IntegrationTests --build-tests clean
    - commit: b0917c5
    - review: clean — 0 findings; task moved to done. The CI run-order box waits for the push.
  timestamp: 2026-08-19T19:39:54.917861+00:00
- actor: claude-code
  id: 01m0drkv72h95x29s0htrnfp3c
  text: 'CI run 32294279325 started on push 563a483. The new order works: only "Unit tests" is in progress, and the integration job waits on the needs edge. When the run completes, record its job times here and check the last acceptance box.'
  timestamp: 2026-08-19T19:40:19.042887+00:00
- actor: claude-code
  id: 01m0fhkcxjzmt5hwbq1h44c1wz
  text: 'CI run 32294279325 proves the order: the unit job completed at 19:43:03Z and the integration job started at 19:43:05Z — two seconds later, only after unit success. The run-order acceptance box is checked. The run''s integration job failed for an unrelated cause (ElevationTests time limit, filed separately).'
  timestamp: 2026-08-20T12:16:13.234182+00:00
position_column: done
position_ordinal: d880
title: 'CI: run the integration job only after the unit job passes'
---
Observed on CI run `32285751680` (push `dad8ba8`, 2026-08-19): the job "Integration (real models, real GPU)" started at 18:09:39 and held the runner for more than an hour, while the job "Unit tests" stayed queued behind it. Both jobs in `.github/workflows/ci.yml` target the same `[self-hosted, macOS]` label, and no `needs:` edge orders them — so GitHub assigns the runner in arbitrary order, and the ~70-minute job can run first. The fast fail signal then comes last. This is the opposite of fail-fast.

Separate context, not this card's work: the red on run `32203706380` is the old canary's 600-second ceiling. Commits `cf55b56` and `cda247d` (task `^nhxj8hx`) already correct that; a push carries them.

## What

- Edit `.github/workflows/ci.yml`: add `needs: unit` to the `integration` job. Effect: the integration job starts only after the unit job succeeds, so a compile error or a unit failure reports in minutes and no 70-minute run starts on a broken tree.
- Keep every existing step of both jobs unchanged — the clean steps, the integration-package build in the unit job (the compile coupling), the metallib copy, and `--no-parallel`.
- Add a comment above `needs:` that states the reason: one runner label, fail-fast order, run `32285751680` as the measurement.
- Add `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`: a unit test that reads `.github/workflows/ci.yml` off disk via the filePath literal (the same shape `HardeningTests.readmeInjectedGlobals()` uses at `HardeningTests.swift:360`) and asserts the `integration:` job declares `needs: unit`. This pins the shipped configuration so a later edit cannot drop the edge without a red unit test.

## Acceptance Criteria

- [x] The `integration` job in `.github/workflows/ci.yml` declares `needs: unit`
- [x] All existing steps of both jobs are unchanged
- [x] `CIWorkflowTests` fails when `needs: unit` is removed, and passes with it present
- [x] On the next CI run, the integration job starts only after the unit job completes — run `32294279325`: unit completed 19:43:03Z, integration started 19:43:05Z (`gh run view 32294279325 --json jobs`)

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift` — new test asserting the workflow's `integration` job carries `needs: unit`
- [x] `swift test` at the repo root — green, zero failures, zero skipped

## Workflow

- Use `/tdd` — write the failing workflow-pinning test first, then edit the workflow to make it pass.

## Review Findings (2026-08-19 14:20)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift:38` `reuse/reuse` — workflowLines() reimplements file-reading boilerplate that already exists in HardeningTests.readmeInjectedGlobals(). Both navigate from up three levels to the repo root, then read a specific file. A shared utility parameterized by the relative path would eliminate this duplication. Extract a shared test utility like `private static func readRepositoryFile(relativePath: String) throws -> String` that both CIWorkflowTests and HardeningTests can call, rather than duplicating the URL navigation boilerplate.

## Review Findings (2026-08-19 14:29)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/RepositoryFile.swift:25` `code-security/injection` — Path traversal vulnerability: `relativePath` parameter is passed to `appendingPathComponent()` without validation, allowing `..` sequences or absolute paths to escape the repository directory. Validate `relativePath` to reject path traversal patterns. Example: `guard !relativePath.contains("..") && !relativePath.hasPrefix("/") else { throw ... }` before line 25.