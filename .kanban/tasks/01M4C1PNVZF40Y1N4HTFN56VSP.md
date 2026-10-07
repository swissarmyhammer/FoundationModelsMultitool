---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: 'git: give the current branch in the tools.git.status result'
---
## What

The `git_status` tool of docker-agent (https://docker.github.io/docker-agent/tools/git/) gives the current branch with the changed files. Our `tools.git.status` gives only the files. `StatusResult` (`Sources/FoundationModelsMultitool/Capabilities/Git/Status.swift:38`) has `staged`, `unstaged`, `untracked`, `renamed`, `isClean`, and `correction`. Thus the model must also call `tools.git.branches` to know the branch.

`LibGit2Repository.currentBranchName()` (`Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Branches.swift:58`) already gives the name, and `tools.git.branches` (`Branches.swift`) already uses it for its `current` field.

- [ ] Add `branch: String?` to `StatusResult`. Its guide must be the same as the guide of `BranchesResult.current` in `Branches.swift`, which also says when the value is null.
- [ ] Fill it in `Status.result(of:)` (`Status.swift:92`). Read the name through the same path that `Branches.swift` uses. Do not add a second repository discovery when one is already open. A failure to read the branch must not hide the lists: give `nil` for `branch`, and keep the lists.
- [ ] `Status.corrective(_:)` gives `branch: nil`.
- [ ] Change the `tools.git.status` rows in `README.md` § "Capabilities" and `git.md` § "Verbs" to name `branch`. Change the contract comment above `struct Status`.

## Acceptance Criteria

- [ ] On a branch, `tools.git.status({}).branch` is that branch name.
- [ ] On a detached HEAD, `branch` is null, and the lists are correct.
- [ ] In a repository with no commit, `branch` is the same value that `tools.git.branches({}).current` gives.
- [ ] A root in no repository gives a `correction` and a null `branch`.
- [ ] `status.branch` and `branches.current` are equal in each test above.

## Tests

- [ ] In `Tests/FoundationModelsMultitoolTests/GitStatusTests.swift`, add one test for each acceptance criterion above. Use `TemporaryGitRepository` and `TestSupport.runGit` (for example `checkout --detach`).
- [ ] Run `swift test --filter GitStatus`. All tests must pass. Then run `swift test`. The full suite must pass with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #git