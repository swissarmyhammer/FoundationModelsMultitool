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
position_column: doing
position_ordinal: '80'
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
- Use `/tdd` — write failing tests first, then implement to make them pass. #git