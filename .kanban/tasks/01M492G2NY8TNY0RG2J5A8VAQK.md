---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m493e6cvgzvy8zxhzf2rqz2x
  text: |-
    Research (before code):
    - Only `GitContext.repositoryPath(of:in:)` (GitBlobReader.swift) sends a history path through the guard. Show (through `blob(path:ref:)`) and Log call it. Blame does not: it uses `validate(_:for: .read)` on a file in the work folder. Diff does not exist yet.
    - `PathGuard.validatePath` refuses ENOENT when the parent folder is absent (`parentDirectoryMissing`). The workspace boundary step already resolves a missing path from its deepest existing folder (`reconstructViaExistingParent`), and its containment test is lexical.
    - `GitRepositoryLocation.realPath(of:)` resolves only the direct folder of a missing file. When that folder is absent too, `resolvedPath` gives the `/var` spelling and the compare with the `/private/var` work folder fails.
    - Decision: add an opt-in rule to the guard, `validatePath(_:absentFolders:)` with `PathGuard.AbsentFolderRule` (`.refused` default, `.accepted`). The default keeps the files behavior. With `.accepted`, all other checks stay (empty, length, blocked pattern, leaf symlink, control characters, boundary from the deepest existing folder). An absent folder that is a dangling symlink (lstat) is still refused, thus no symlink rule gets weaker. The git side resolves the deepest existing folder with realpath and folds `.`/`..` lexically below it.
    - Why not the card example (guard on the nearest existing folder + lexical rest): it skips the length and control-character checks on the rest, and it refuses a symlink folder that the present guard resolves and bounds.
  timestamp: 2026-10-06T17:16:03.355862+00:00
- actor: claude-code
  id: 01m493zxrvdnhgrbe8y6d66mwk
  text: |-
    Implementation landed (TDD).
    - RED 1: compile failure "extra argument 'absentFolders' in call". RED 2 (after the guard): GitContextTests absent-folder tests failed (`/var` vs `/private/var`, nil), Show/Log tests failed with the "Parent directory does not exist" correction. GREEN at the first run after each change.
    - Mutation check: with the dangling-symlink check removed, `rejectsADanglingSymlinkAmongAbsentFolders` fails for both `allowSymlinks` values. Check restored.
    - PathGuard: `enum AbsentFolderRule { refused, accepted }`; `validatePath(_:absentFolders: = .refused)`. The default keeps the files behavior (all callers of files use the default). `.accepted` replaces only the parent-exists rule with `danglingSymlinkFolderViolation`: it walks up the absent folders and refuses one that `lstat` sees as a symlink ("Path goes through a dangling symlink: ..."), also when symlinks are allowed. Length, blocked pattern, leaf symlink, control characters, and the boundary (from the deepest existing folder, via `reconstructViaExistingParent`) are unchanged.
    - GitRepositoryLocation: `realPath(of:)` became `realComponents(of:)`: realpath of the deepest part on the disk + the absent parts, with `.`/`..` folded by a shared `appending(_:to:)`, which `repositoryPath(fromRootRelativePath:)` uses too.
    - GitBlobReader `repositoryPath(of:in:)` uses `.accepted`. Show and Log both read through it. Blame is unchanged (it reads the work folder file with the `read` permission).
    - Divergence to note: git.md decision 8 says the git `PathGuard` has "the same rules as `files`". It is the same guard, but history path arguments now use `AbsentFolderRule.accepted`. git.md was not changed (not on the card); it needs one sentence under decision 8.
  timestamp: 2026-10-06T17:25:44.347365+00:00
- actor: claude-code
  id: 01m49400j1zr6yaz3jb596av6v
  text: |-
    ### implement — changed
    - evidence: 8 files. Sources/FoundationModelsMultitool/Capabilities/Files/PathGuard.swift, Capabilities/Git/GitRepositoryLocation.swift, Capabilities/Git/GitBlobReader.swift; Tests/FoundationModelsMultitoolTests/{PathGuardTests,GitContextTests,GitShowTests,GitLogTests,GitTestHistory}.swift. `swift package update` OK. `swift build --build-tests`: 0 errors, only the known mlx-swift "missing creator for mutated node" warning. `swift test`: 1950 tests in 166 suites pass (was 1940). IntegrationTests `swift build --build-tests`: Build complete, same known warning only.
    - next: /review. The task stays in `doing`. Not committed, not pushed.
  timestamp: 2026-10-06T17:25:47.201850+00:00
- actor: claude-code
  id: 01m494486pb7aqj5amjtdrebhp
  text: |-
    ### test - green
    - evidence: swift build --build-tests - complete, exit 0. swift test - 1950 tests in 166 suites passed, 0 failed, 0 skipped. Files suites passed: PathGuardTests, FilesReadTests, FilesWriteTests, FilesEditTests, FilesPatchTests, FilesGlobTests, FilesGrepTests, FilesCapabilityTests, FilesCrossOpFlowTests. cd IntegrationTests && swift build --build-tests - complete, exit 0.
    - warnings: only the known dependency warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle (in the main package and in IntegrationTests). It was there before this change. No other warning.
    - next: review
  timestamp: 2026-10-06T17:28:06.102663+00:00
- actor: claude-code
  id: 01m4944r7w081y0f8avfb7gw3k
  text: |-
    ### commit — changed
    - evidence: one local commit with subject "fix: let git show and log read a path whose folder is gone from the work folder". The sha is in git log. This comment is inside that commit, so the sha is not written here.
    - files: PathGuard.swift, GitRepositoryLocation.swift, GitBlobReader.swift, the changed git and PathGuard tests, git.md (decision 8 names the exception), and .kanban/ changes.
    - next: review. The commit was not pushed.
  timestamp: 2026-10-06T17:28:22.524768+00:00
- actor: claude-code
  id: 01m494dbfv934pv8y2rk8kn7qm
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit e065354). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. The engine reviewed 8 files, which include Capabilities/Files/PathGuard.swift. The commit does not rename a file. The engine did not review 4 .kanban files (.reviewignore) and git.md (no validator matches).
    - next: none. The task moved to done.
  timestamp: 2026-10-06T17:33:04.379632+00:00
- actor: claude-code
  id: 01m494dt3mf8sry5zmhcss8srj
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files (PathGuard.swift, GitRepositoryLocation.swift, GitBlobReader.swift, 5 test files); git.md decision 8 updated by the orchestrator
    - test: green — swift test, 1950 passed in 166 suites (all 9 files suites pass); IntegrationTests build complete
    - commit: e065354
    - review: clean — 0 findings, 7 validators on 8 files (PathGuard.swift included)
  timestamp: 2026-10-06T17:33:19.348763+00:00
position_column: done
position_ordinal: ffffaf80
title: 'git: show and log for a path whose folder is gone from the work folder'
---
## Problem

`GitContext.blob(path:ref:)` (`Capabilities/Git/GitBlobReader.swift`) and `tools.git.log` send each path through `PathGuard.validatePath`. The guard accepts a missing file only when its parent folder is on the disk. Thus `tools.git.show({ path: "old/dir/a.txt", ref: "HEAD~5" })` gives the correction "Parent directory does not exist" when a later commit removed the folder `old/dir`. The `git` command reads that file. `tools.git.diff` with `path@ref` reads through the same reader and has the same gap.

Found during `^w0yeya3`.

## Work

1. Decide how a history path goes through the guard when its folder is absent. For example: check the nearest folder that is on the disk with the guard, and check the rest of the path with the lexical rules (no `..`, no absolute path) through `GitRepositoryLocation.repositoryPath(fromRootRelativePath:)`.
2. Keep the rule that a path cannot go out of the root.

## Tests

- `show` of a file in a folder that a later commit removed, at an older ref.
- `log` with that path.
- A path outside the root is still a correction. #git