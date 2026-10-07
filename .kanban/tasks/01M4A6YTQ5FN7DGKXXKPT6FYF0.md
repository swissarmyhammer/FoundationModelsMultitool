---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4a7w3ne69gz16aah3eedfwp
  text: |-
    Research and implementation (TDD).

    Research:
    - `GitStatusReader.readStatus(in:)` maps each group list through `rootRelativePath(fromRepositoryPath:)`. A rename entry holds the NEW path, thus a rename to a path outside the root fell out of every list. `LibGit2Status.oldPathsOfRenamedFiles` (from ^wvmh7vf) already holds new path -> old path for each staged rename, thus the LibGit2 layer needed no change.
    - `Status.result(of:)` copies `status.staged` and `status.isClean` without change, and `Diff.automaticDiff()` diffs each path of `status.allFiles`. Thus a change in the reader reaches `tools.git.status`, `tools.git.changes` (`allFiles`), and the automatic mode of `tools.git.diff`.
    - `Diff.automaticChange(ofFile:renamedFrom:)` with the old path and no rename entry reads HEAD at that path (below the root) and finds no file in the work folder, thus `fileStatus` gives `.deleted`, and the engine gives each entity as `deleted`. Diff.swift needed only a header comment.

    Decision:
    - New private `GitContext.removalsOfRenamesOutOfTheRoot(of:in:)` in GitStatusReader.swift: each old path of a rename whose new path is outside the root and whose old path is below the root, as a root path, sorted (the source is a Dictionary, thus `sorted()` makes the order stable). `staged` is `paths(.staged)` plus this list. The new path is never given or read (git.md decision 8). `oldPathsOfRenamedFiles` does not change: it keeps an entry only when both paths are below the root.
    - libgit2 with RENAMES_HEAD_TO_INDEX uses only a deleted file as a rename source, thus the old path is not also in `paths(.staged)`.

    RED: GitStatusReaderTests "a rename to outside the root is a staged removal of the old path" failed (status was empty, isClean true). GitDiffTests "automatic mode gives a rename to outside the root as deleted" failed (deleted 0, no change). GREEN: both pass after the reader change.
  timestamp: 2026-10-07T03:52:48.046963+00:00
- actor: claude-code
  id: 01m4a7w6nysn90mpe4bvy49zve
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift, Sources/FoundationModelsMultitool/Capabilities/Git/Diff.swift (header comment only), Tests/FoundationModelsMultitoolTests/GitStatusReaderTests.swift, Tests/FoundationModelsMultitoolTests/GitDiffTests.swift. `swift package update`: up to date. `swift build --build-tests`: complete. `swift test`: 2227 tests in 191 suites passed (2225 before + 2 new), 0 failed. IntegrationTests `swift build --build-tests`: complete. Only warning: the known mlx-swift "missing creator for mutated node" dependency warning.
    - next: /review. The task stays in `doing`. Not committed, not pushed.
  timestamp: 2026-10-07T03:52:51.134140+00:00
- actor: claude-code
  id: 01m4a80dzddx4grby8np47aszk
  text: |-
    ### test - green
    - evidence: swift build --build-tests exit 0. swift test: 2227 tests in 191 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests exit 0.
    - warnings: only "missing creator for mutated node" for mlx-swift_Cmlx.bundle. This is a dependency warning from before this change. It is not red.
    - next: review.
  timestamp: 2026-10-07T03:55:09.677766+00:00
- actor: claude-code
  id: 01m4a810hbhe0ax72jkxn9zj7q
  text: |-
    ### commit — changed
    - evidence: one local commit, subject "fix: list rename from below root to outside root in git status". It holds GitStatusReader.swift, Diff.swift, GitStatusReaderTests.swift, GitDiffTests.swift and all .kanban changes (with the leftover task files from the review of ^wvmh7vf). No build product is staged. No push.
    - next: test and review
  timestamp: 2026-10-07T03:55:28.683135+00:00
- actor: claude-code
  id: 01m4a8952s9mkh5msgknrfm9a6
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 25d910d). 0 findings, 0 confirmed, 0 refuted. 7 pairs attempted, 0 failed. 4 source files reviewed. 4 `.kanban/` files are excluded by `.reviewignore`. The commit renames no file, thus no file-scoped review was necessary.
    - next: The task is in `done`. No work stays open.
  timestamp: 2026-10-07T03:59:55.481519+00:00
- actor: claude-code
  id: 01m4a89gdy34vpczf9jzkrqfmk
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files (GitStatusReader.swift, Diff.swift, GitStatusReaderTests.swift, GitDiffTests.swift)
    - test: green — swift test, 2227 passed in 191 suites; IntegrationTests build complete
    - commit: 25d910d
    - review: clean — 0 findings, 7 validators on 4 files
  timestamp: 2026-10-07T04:00:07.102292+00:00
position_column: done
position_ordinal: ffffbb80
title: 'git: a rename from below the root to outside the root is in no status list'
---
## Goal

Decide and test what `GitContext.status()` gives when a staged rename moves a file from a path below the root to a path outside the root.

## Facts

- `GitStatusReader.readStatus(in:)` keeps a path only when `rootRelativePath(fromRepositoryPath:)` gives a value. A rename entry has the NEW path, thus a rename to a path outside the root is dropped from every list.
- With `GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX`, libgit2 gives no separate deleted entry for the old path. Thus the root does not show that its file is gone: `tools.git.status` can say `isClean == true`, and the automatic mode of `tools.git.diff` does not give the entities of the old file as `deleted`.
- Found during task ^wvmh7vf (the opposite case: a rename from outside the root into the root; there the file is new below the root and its entities are `added`).

## Work

1. Write a failing test in `GitStatusReaderTests` for a rename from `src/old.txt` to `outside.txt` with the root at `src/`.
2. Give the old path as a staged removal below the root (the root rule, git.md decision 8, allows it: the old path is below the root), and make the automatic diff give its entities as `deleted`.
3. Keep the existing tests green. #git