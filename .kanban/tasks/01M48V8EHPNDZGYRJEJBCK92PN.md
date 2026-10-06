---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m49aks2bmnskm9g8ynvs2fsx
  text: |-
    Research (before code):
    - Pattern: `Log.swift`/`Show.swift` (verb: `@Generable` arguments and result, `correction` in band, `context.repository.resolve(corrective:then:)`), `GitBlobReader.swift` (shared reader as a `GitContext` extension), LibGit2 layer files (`LibGit2Log.swift` etc., `LibGit2.makeHandle`, `LibGit2.check`, typed throws).
    - Rust `get_status`: `include_untracked` + `recurse_untracked_dirs`, no ignored, NO rename detection (thus its `renamed` bucket stays empty in practice). git.md "Spike result" proved `git_status_list_new` with `GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX`. Plan: the same flags as Rust plus head-to-index renames.
    - Rust `get_current_branch`: unborn HEAD -> None. Its `shorthand()` gives "HEAD" for a detached HEAD; the card wants nil. Plan: `git_repository_head`, then `git_reference_is_branch`; unborn (`GIT_EUNBORNBRANCH`) -> nil.
    - Rust `main_branch`: `main` if the local branch exists, else `master`, else error. Plan: the verb decides from the local branch list, `nil` in place of the error.
    - Reuse plan for `changes`/`diff`: the status read is `GitContext.status() -> Result<GitStatus, CorrectiveRejection>` in a new `GitStatusReader.swift` (the same shape as `GitBlobReader.swift`). It gives root-relative lists and drops a path outside the root. The C calls go in `LibGit2Status.swift` and `LibGit2Branches.swift`.
    - Mapping (a table in the layer): INDEX_NEW/MODIFIED/DELETED/TYPECHANGE -> staged; INDEX_RENAMED -> renamed (the new path); WT_MODIFIED/DELETED/TYPECHANGE/UNREADABLE and CONFLICTED -> unstaged; WT_NEW -> untracked. The card names no `conflicted` list; a conflicted file goes in `unstaged`, so `isClean` is never true for it.
    - `libGit2True` is private in `LibGit2Blame.swift`; the branch read needs the same constant, thus it moves to `LibGit2`.
    - Naming rule: the card field `clean` is `isClean` (swift/naming-clarity). Idiom rule: `case .x(let a)`.
    - No golden covers `withGit` (BuilderSurface.ts.txt has no git entry), thus no golden changes.
  timestamp: 2026-10-06T19:21:26.347599+00:00
- actor: claude-code
  id: 01m49b55xnhvwrx8aq0nsabqdt
  text: |-
    Implementation landed (TDD: RED was the compile failure "GitContext has no member 'status'", "cannot find 'GitStatus'", "LibGit2Repository has no member 'localBranchNames' / 'currentBranchName'". GREEN at the first run after one fix: the libgit2 1.9 name is `git_status_list_entrycount`, not `git_status_entrycount`).

    Decisions inside the card:
    - Status result: `staged`, `unstaged`, `untracked`, `renamed`, `isClean` (the card says `clean`; swift/naming-clarity requires `isClean`), `correction?`. A correction gives empty lists and `isClean == false`.
    - Shared reader for `changes`/`diff`: `GitContext.status() -> Result<GitStatus, CorrectiveRejection>` (`GitStatusReader.swift`). `GitStatus` has the four root-relative lists and `isClean`. A path outside the root is dropped with `GitRepositoryLocation.rootRelativePath(fromRepositoryPath:)`.
    - LibGit2 layer: `LibGit2Status.swift` (`LibGit2StatusGroup` enum with an exhaustive `flags` switch as the table, `LibGit2StatusEntry`, `LibGit2Status.paths(in:)`, `status()` with INCLUDE_UNTRACKED + RECURSE_UNTRACKED_DIRS + RENAMES_HEAD_TO_INDEX). `LibGit2Branches.swift` (`localBranchNames()`, `currentBranchName()`).
    - The card names no conflicted list: GIT_STATUS_CONFLICTED goes to `unstaged`, thus `isClean` is never true with a conflict.
    - Branches result: `branches` (sorted by name, so the order is stable), `current` (nil for a detached HEAD and for a repository with no commit), `main` (`main`, else `master`, else nil), `correction?`.
    - `libGit2True` (private in LibGit2Blame.swift) moved to `LibGit2.trueValue`, because `currentBranchName()` needs it too (`git_reference_is_branch`).
    - Empty `@Generable struct StatusArguments {}` / `BranchesArguments {}` compile, and the surface renders them (GitCapabilityTests pass).
    - Test support: `TemporaryGitRepository.stage(_:)` now also stages a removal (file absent -> `git_index_remove_bypath`); new `markConflicted(_:)`, `pointHead(atBranch:)`, `detachHead()`, `deleteBranch(named:)`.

    Discoveries:
    - Rust `get_current_branch` uses `shorthand()`, which gives "HEAD" for a detached HEAD. This port gives nil (the card asks for that).
    - Rust `get_status` does not turn on rename detection, thus its `renamed` bucket is empty in practice. This port turns on head-to-index renames (proved in the spike).
    - No golden covers `withGit`, thus no golden changed. No ARCHITECTURE.md exists.
  timestamp: 2026-10-06T19:30:56.565937+00:00
- actor: claude-code
  id: 01m49b5bdsmvxygky96m9zbe74
  text: |-
    ### implement — changed
    - evidence: 15 files. New: Sources/FoundationModelsMultitool/Capabilities/Git/{Status,Branches,GitStatusReader}.swift, Capabilities/Git/LibGit2/{LibGit2Status,LibGit2Branches}.swift, Tests/FoundationModelsMultitoolTests/{GitStatusTests,GitStatusReaderTests,GitBranchesTests,LibGit2StatusTests,LibGit2BranchesTests}.swift. Changed: Capabilities/Git/GitCapability.swift (tools + doc), Capabilities/Git/LibGit2/LibGit2.swift (`trueValue`), Capabilities/Git/LibGit2/LibGit2Blame.swift (uses `LibGit2.trueValue`), Tests/Support/MultitoolTestSupport/TemporaryGitRepository.swift, Tests/FoundationModelsMultitoolTests/GitCapabilityTests.swift. `swift package update`: up to date. `swift build --build-tests`: 0 errors, only the known mlx-swift "missing creator for mutated node" warning. `swift test`: 2068 tests in 178 suites pass. IntegrationTests `swift build --build-tests`: Build complete, same known warning only.
    - next: /review. The task stays in `doing`. Not committed, not pushed.
  timestamp: 2026-10-06T19:31:02.201069+00:00
- actor: claude-code
  id: 01m49b8r9yy7bev88apkg9f73r
  text: |-
    ### test - green
    - evidence: swift build --build-tests - complete. swift test - 2068 tests in 178 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests - complete.
    - warnings: only "missing creator for mutated node" for mlx-swift_Cmlx.bundle. This is a dependency warning from before this change. It is not red.
    - next: review
  timestamp: 2026-10-06T19:32:53.694124+00:00
- actor: claude-code
  id: 01m49b97rn47466v2064z1mp34
  text: |-
    ### commit — changed
    - evidence: one local commit, subject "feat: add status and branches to git capability". The sha is in git log, because this comment ships inside the commit.
    - scope: Status, Branches, GitStatusReader, LibGit2Status, LibGit2Branches, changed Git and LibGit2 files, test support, tests, .kanban changes.
    - next: review. No push was done.
  timestamp: 2026-10-06T19:33:09.525902+00:00
- actor: claude-code
  id: 01m49bq64h7tvbmsgd6rmhqvgn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 2aaf8ac). The engine reviewed 15 files. It found 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed). The .reviewignore rule excluded 4 .kanban files. The commit renames no file, thus no file-scoped review was necessary. The task has no prior Review Findings sections.
    - next: none. The task moved to done.
  timestamp: 2026-10-06T19:40:46.609371+00:00
- actor: claude-code
  id: 01m49bqjr7zhses0e26m8f2cb0
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 15 files (Status, Branches, GitStatusReader, LibGit2Status, LibGit2Branches, 5 new test suites, helper and capability changes)
    - test: green — swift test, 2068 passed in 178 suites; IntegrationTests build complete
    - commit: 2aaf8ac
    - review: clean — 0 findings, 7 validators on 15 files
  timestamp: 2026-10-06T19:40:59.527220+00:00
depends_on:
- 01M48V80WKJ4QSW2TXPQ01E3QN
position_column: done
position_ordinal: ffffb380
title: 'git: tools.git.status and tools.git.branches'
---
## Goal

Add the two simplest read verbs (git.md, "Verbs").

## Source

- `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`: `get_status` (line 336), `list_local_branches` (126), `get_current_branch` (104), `main_branch` (687).
- `swissarmyhammer-git/src/types.rs`: `StatusSummary`.

## Work

1. `Status` verb (`name = "status"`), no arguments. Result: `staged`, `unstaged`, `untracked`, `renamed` (each a list of paths relative to the root), `clean: Bool`, and `correction: String?`.
2. `Branches` verb (`name = "branches"`), no arguments. Result: `branches` (local), `current` (nil when HEAD is detached), `main` (`main`, else `master`, else nil), and `correction: String?`.
3. Each verb is a plain `FoundationModels.Tool` with `@Generable` arguments and result, in the pattern of `Capabilities/Files/Glob.swift`. Each field has a `@Guide` description.
4. A file outside the root (but in the repository) does not show in a result.
5. Add both verbs to `GitCapability.tools`.

## Tests

Use the temporary-repository helper.
- Clean repository: `clean == true`, all lists empty.
- One file of each kind: staged, unstaged, untracked, renamed.
- Root in a subfolder: paths are relative to the root; files outside the root are not listed.
- Branches: current branch, a second branch, detached HEAD, `main` versus `master`.
- Root not in a repository: a `correction`, no throw.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- The rendered surface (golden files under `Tests/.../Goldens`) shows the two verbs, if a golden covers `withGit`. #git