---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c6mzj9vpftfey1qgetpz78
  text: 'Research: `GitContext.status()` (GitStatusReader.swift) already opens one `LibGit2Repository` in `readStatus(in:)`. Thus the branch is read there, from the same open repository, with `try? repository.currentBranchName()`, and goes into a new `GitStatus.branch`. This gives no second repository discovery. A failure to read HEAD gives `nil` and keeps the lists. `Status.result(of:)` copies `status.branch`; `Status.corrective(_:)` gives `branch: nil`. Note: `tools.git.changes` (Changes.swift) still discovers the repository two times (reader plus its own open); that is outside this card. The three `GitStatus(...)` equality checks in GitStatusReaderTests now name `branch: TemporaryGitRepository.defaultBranch`. `TemporaryGitRepository.detachHead()` is the existing helper for a detached HEAD; the tests use it in place of `runGit checkout --detach`.'
  timestamp: 2026-10-07T22:09:54.761101+00:00
- actor: claude-code
  id: 01m4c6n2acwebq6bkwktb9z1zt
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift, Sources/FoundationModelsMultitool/Capabilities/Git/Status.swift, Tests/FoundationModelsMultitoolTests/GitStatusTests.swift (4 new tests), Tests/FoundationModelsMultitoolTests/GitStatusReaderTests.swift, README.md, git.md. RED: `swift test --filter GitStatusTests` failed to compile (`StatusResult` has no member `branch`). GREEN: `swift test --filter GitStatus` 20 tests in 2 suites passed. Full: `swift test` 2272 tests in 196 suites passed. The one build line `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle` comes from the SwiftPM build graph of the mlx dependency, not from a changed file.
    - next: /review
  timestamp: 2026-10-07T22:09:57.580894+00:00
- actor: claude-code
  id: 01m4c6qdmncg1ktd42yfq0at25
  text: |-
    ### test - green
    - evidence: swift test - 2272 tests in 196 suites passed, 0 failed, 0 skipped.
    - warnings: one build warning only. It is "missing creator for mutated node" from the mlx dependency (mlx-swift_Cmlx.bundle). It is not caused by project code.
    - note: Package.resolved was not changed. The local FoundationModelsRanker pin to d75a67c stays.
    - next: review.
  timestamp: 2026-10-07T22:11:14.709821+00:00
- actor: claude-code
  id: 01m4c6yrwe6z52z4hx9j374frn
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (b2f51b8); 2 findings, 2 confirmed, 0 refuted — Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift:127 (completeness/public-output-contract), Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift:127 (swift/preconditions)
    - next: implement the two open items in the "Review Findings (2026-10-07 17:11)" section. Keep the nil branch and the lists. Do not silence the HEAD read error with try?.
  timestamp: 2026-10-07T22:15:15.598886+00:00
- actor: claude-code
  id: 01m4c6z79gm9ek02jsf8ns3wez
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 2272 passed
    - commit: b2f51b8
    - review: findings — GitStatusReader.swift:127 (completeness/public-output-contract), GitStatusReader.swift:127 (swift/preconditions)
  timestamp: 2026-10-07T22:15:30.352150+00:00
- actor: claude-code
  id: 01m4c72jdq6t8kcxyb00jbsgyy
  text: 'Research for the two review findings: Sources has no `assertionFailure` yet. The log pattern of the library is `MultitoolTelemetry.logger.log(.<LogMessage case>, level:, metadata: MultitoolTelemetry.errorMetadata(of: error))` (for example `ToolAPIRenderer.reportWidening`, `SurfaceRefresher`). A log message is a constant `MultitoolTelemetry.LogMessage` case; variable values go in metadata only. Plan: add `LogMessage.gitBranchReadFailed` (level `error`), replace `try? repository.currentBranchName()` with a do/catch helper that calls `assertionFailure` and logs, and keeps `branch: nil` and the lists. For finding 1, the status contract keeps the lists, thus a correction beside the lists is not possible (`correction` and the lists are exclusive). The `branch` Guide and the tool description of `tools.git.status` now also say that null can mean HEAD could not be read; thus the Guide is the Guide of `BranchesResult.current` plus that one clause. `tools.git.branches` gives a correction for that failure, thus its Guide does not need the clause. `currentBranchName()` returns nil (not throws) for GIT_EUNBORNBRANCH, thus the no-commit test does not hit the assertion. The failure path itself cannot have a unit test: the assertion stops a debug test run.'
  timestamp: 2026-10-07T22:17:20.055213+00:00
- actor: claude-code
  id: 01m4c798nc7pcctq74mgz32jvh
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift (the `try?` is replaced by `currentBranchName(of:)`: do/catch, `assertionFailure`, an `error` log record `.gitBranchReadFailed` with `errorMetadata`, and `nil`; the lists stand), Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift (new `LogMessage.gitBranchReadFailed`), Sources/FoundationModelsMultitool/Capabilities/Git/Status.swift (the `branch` Guide, the tool description, and the contract comment say that null can also mean HEAD could not be read), Tests/FoundationModelsMultitoolTests/GitStatusTests.swift (2 new tests: the Guide and the description name that case), README.md, git.md. RED: `swift test --filter "GitStatusTests/the"` 2 tests failed (the Guide and the description had no such text). GREEN: `swift test --filter GitStatus` 22 tests in 2 suites passed. Full: `swift test` 2274 tests in 196 suites passed, 0 failed. No test hit the new assertion. The one build line `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle` comes from the mlx dependency, as before.
    - note: the failure path itself has no unit test, because the assertion stops a debug test run. The `branch` Guide is the Guide of `BranchesResult.current` plus one sentence for this verb, because `tools.git.branches` answers that failure with a correction and `tools.git.status` keeps its lists.
    - next: /review
  timestamp: 2026-10-07T22:20:59.436802+00:00
- actor: claude-code
  id: 01m4c7c14bpfpgc1nnjp6ymz8s
  text: |-
    ### test - green
    - evidence: swift test - 2274 tests in 196 suites passed, 0 failed, 0 skipped.
    - warnings: one warning only. It is "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It comes from the mlx dependency. It is not ours.
    - note: Package.resolved was not changed. FoundationModelsRanker pin d75a67c stays. No commit made.
    - next: review.
  timestamp: 2026-10-07T22:22:30.027156+00:00
- actor: claude-code
  id: 01m4c7h3435bcsv7mc5p61jdnp
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 80b527e) gave 0 findings (7 attempted, 1 refuted, 0 failed). All items in the prior Review Findings section are checked.
    - next: The task is in done. No more work is necessary.
  timestamp: 2026-10-07T22:25:15.907970+00:00
- actor: claude-code
  id: 01m4c7hj25htt1m36d4dnvvce6
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 6 files (no try? on the branch read; assertionFailure + gitBranchReadFailed log; Guide and docs say null can mean HEAD could not be read)
    - test: green — swift test, 2274 passed
    - commit: 80b527e
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-07T22:25:31.205436+00:00
position_column: done
position_ordinal: ffffc680
title: 'git: give the current branch in the tools.git.status result'
---
## What

The `git_status` tool of docker-agent (https://docker.github.io/docker-agent/tools/git/) gives the current branch with the changed files. Our `tools.git.status` gives only the files. `StatusResult` (`Sources/FoundationModelsMultitool/Capabilities/Git/Status.swift:38`) has `staged`, `unstaged`, `untracked`, `renamed`, `isClean`, and `correction`. Thus the model must also call `tools.git.branches` to know the branch.

`LibGit2Repository.currentBranchName()` (`Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Branches.swift:58`) already gives the name, and `tools.git.branches` (`Branches.swift`) already uses it for its `current` field.

- [x] Add `branch: String?` to `StatusResult`. Its guide must be the same as the guide of `BranchesResult.current` in `Branches.swift`, which also says when the value is null.
- [x] Fill it in `Status.result(of:)` (`Status.swift:92`). Read the name through the same path that `Branches.swift` uses. Do not add a second repository discovery when one is already open. A failure to read the branch must not hide the lists: give `nil` for `branch`, and keep the lists.
- [x] `Status.corrective(_:)` gives `branch: nil`.
- [x] Change the `tools.git.status` rows in `README.md` § "Capabilities" and `git.md` § "Verbs" to name `branch`. Change the contract comment above `struct Status`.

## Acceptance Criteria

- [x] On a branch, `tools.git.status({}).branch` is that branch name.
- [x] On a detached HEAD, `branch` is null, and the lists are correct.
- [x] In a repository with no commit, `branch` is the same value that `tools.git.branches({}).current` gives.
- [x] A root in no repository gives a `correction` and a null `branch`.
- [x] `status.branch` and `branches.current` are equal in each test above.

## Tests

- [x] In `Tests/FoundationModelsMultitoolTests/GitStatusTests.swift`, add one test for each acceptance criterion above. Use `TemporaryGitRepository` and `TestSupport.runGit` (for example `checkout --detach`).
- [x] Run `swift test --filter GitStatus`. All tests must pass. Then run `swift test`. The full suite must pass with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 17:11)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 6 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `git.md` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift:127` `completeness/public-output-contract` — The branch read uses `try? repository.currentBranchName()`, so a libgit2 failure to read HEAD is silenced and returns `nil`. That is the same value a detached HEAD gives, so the model cannot tell an unreadable HEAD from a detached one. The error is dropped with no warning, log, or correction. Either surface the failure in the result, for example as a correction beside the lists, or state in the `branch` Guide and the tool description that `null` can also mean HEAD could not be read. Add a test for the read-failure path if it is meant to be a supported outcome.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift:127` `swift/preconditions` — The branch read uses `try?`, so a libgit2 error that reads HEAD is dropped with no assertion and no log. The reader then gives a `nil` branch, the same value as a detached HEAD, and the defect stays hidden. HEAD should always be readable, so this is an unexpected condition that the code answers with silence. Keep the `nil` branch for the lists, but record the failure. Use `do { branch = try repository.currentBranchName() } catch { assertionFailure("HEAD could not be read: \(error)"); logger.error("HEAD could not be read; the branch is left out: \(error)"); branch = nil }`. If the project has no logger in this capability, the reviewer should confirm that before applying this fix. #git