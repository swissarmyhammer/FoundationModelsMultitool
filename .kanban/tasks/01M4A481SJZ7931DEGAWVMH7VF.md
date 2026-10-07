---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4a6zbpdn6b17knd6nfn0d75
  text: |-
    Research and implementation (TDD).

    Research:
    - `LibGit2Status.statusEntry(of:)` copied only `new_file.path`. `GitStatusReader` mapped each group list through `rootRelativePath(fromRepositoryPath:)`. `Diff.automaticChange(ofFile:)` read `HEAD:<path>` with `oldFilePath: nil`.
    - `SemanticDiffer` already reads the old entities at `file.oldFilePath ?? file.filePath`. Entity ids hold the file path, thus with the old path set, phase 2 (same content hash) gives `moved` with `oldFilePath`, and phase 3 (token Jaccard >= 0.8) pairs a changed function across two paths.

    Decisions:
    - LibGit2 layer: `LibGit2StatusEntry.oldPath: String?` (only for an entry with `GIT_STATUS_INDEX_RENAMED`, from `head_to_index.old_file.path`), and `LibGit2Status.oldPathsOfRenamedFiles: [String: String]` (new path -> old path).
    - `GitStatus.oldPathsOfRenamedFiles: [String: String]` (root-relative new path -> root-relative old path). An entry stays only when BOTH paths are below the root. `tools.git.status` result shape did not change. The two `GitStatus(...)` literals in GitStatusReaderTests now pass `oldPathsOfRenamedFiles: [:]` (memberwise init; no default parameter in production code only for tests).
    - `Diff`: `automaticChange(ofFile:renamedFrom:)` reads HEAD at `oldPath ?? path` and sets `oldFilePath`; `fileStatus(before:after:isRenamed:)` gives `.renamed` for a rename with both sides. The file header states this is a deliberate fix of the Rust gap (`populate_staged_contents` reads `HEAD:<new path>`).
    - Root rule (git.md decision 8): a rename from a path outside the root has no old path in `GitStatus`, thus the old path is never read; the file is new below the root and its entities are `added` with `oldFilePath == nil`. Tested in GitStatusReaderTests and GitDiffTests.
    - Test helper: `TemporaryGitRepository.stageRename(from:to:)`.

    What did not work:
    - The first fixture for "a staged rename with a changed function" used the one-line `greet` body ("hello" -> "hello, world"). The engine gave `deleted` + `added`: the token Jaccard is 0.7, under `EntityMatcher.fuzzyMatchThreshold` (0.8). The read of the old path was correct (a `deleted` change appeared, which needs the old side). The fixture now uses a function with a longer body and one changed line (`return sum` -> `return sum * 2`), which the engine pairs as `moved`.

    Discovery: a rename from below the root to a path outside the root is in no status list, thus the root does not see that its file is gone. Follow-up task ^pt6fyf0.

    RED: build failed with "value of type 'GitStatus' has no member 'oldPathsOfRenamedFiles'"; after the layer change, the two in-root diff tests failed (entities `added`, `oldFilePath` nil). GREEN: GitDiffTests 31/31. Note: the outside-root diff test passed before the Diff change too; it guards the root rule, not the new read.
  timestamp: 2026-10-07T03:37:05.997770+00:00
- actor: claude-code
  id: 01m4a6zhbsnrdr7stbtx1vbrrg
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Status.swift, Sources/FoundationModelsMultitool/Capabilities/Git/GitStatusReader.swift, Sources/FoundationModelsMultitool/Capabilities/Git/Diff.swift, Tests/Support/MultitoolTestSupport/TemporaryGitRepository.swift, Tests/FoundationModelsMultitoolTests/LibGit2StatusTests.swift, Tests/FoundationModelsMultitoolTests/GitStatusReaderTests.swift, Tests/FoundationModelsMultitoolTests/GitDiffTests.swift. `swift package update`: up to date. `swift build --build-tests`: Build complete, only the known mlx-swift "missing creator for mutated node" warning. `swift test`: 2225 tests in 191 suites passed. IntegrationTests `swift build --build-tests`: Build complete, same known warning only. Follow-up task ^pt6fyf0.
    - next: /review. The task stays in `doing`. Not committed, not pushed.
  timestamp: 2026-10-07T03:37:11.801237+00:00
- actor: claude-code
  id: 01m4a74454t2d4r3hcmq585b0b
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` complete. `swift test` ran 2225 tests in 191 suites: all passed, 0 failed, 0 skipped. `cd IntegrationTests && swift build --build-tests` complete.
    - warnings: only the known dependency warning "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It was there before this change. No other warning.
    - next: review
  timestamp: 2026-10-07T03:39:42.116251+00:00
- actor: claude-code
  id: 01m4a74r3n1250q0fhqvkyq7d8
  text: |-
    ### commit — changed
    - evidence: one local commit with subject "fix: read old path of staged rename in git diff automatic mode". It holds LibGit2Status.swift, GitStatusReader.swift, Diff.swift, TemporaryGitRepository.swift, three test files, and all .kanban changes (review leftovers of ^q102ags and new task ^pt6fyf0). The sha is in the commit itself. Run `git log -1` to read it.
    - next: none. The commit is local only. It is not pushed.
  timestamp: 2026-10-07T03:40:02.549024+00:00
- actor: claude-code
  id: 01m4a7dpf01g7w59xpfd25hzy3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 1fc29d3). 0 findings, 0 confirmed, 0 refuted. 7 files reviewed, 0 failed. 6 .kanban files are excluded by .reviewignore. The commit renames no file, thus no file-scoped review is necessary.
    - next: The task is in done. No more work.
  timestamp: 2026-10-07T03:44:55.776515+00:00
- actor: claude-code
  id: 01m4a7e3f68ce7pkrnb2e874mj
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (LibGit2Status.swift, GitStatusReader.swift, Diff.swift, TemporaryGitRepository.swift, 3 test files); follow-up ^pt6fyf0
    - test: green — swift test, 2225 passed in 191 suites; IntegrationTests build complete
    - commit: 1fc29d3
    - review: clean — 0 findings, 7 files reviewed
  timestamp: 2026-10-07T03:45:09.094795+00:00
position_column: done
position_ordinal: ffffba80
title: 'git: diff automatic mode reads the old path of a staged rename'
---
## Goal

In the automatic mode of `tools.git.diff` (`Sources/FoundationModelsMultitool/Capabilities/Git/Diff.swift`), a staged rename must diff the file at HEAD under its OLD path against the work folder file under its new path. Then the entities of the file are `moved`, `renamed`, or `modified`, not `added`.

## Facts

- `LibGit2Status.statusEntry(of:)` copies only `new_file.path`. `GitStatus.renamed` holds only the new path.
- `Diff.automaticChange(ofFile:)` reads HEAD at the new path. HEAD does not hold it, thus each entity is `added`, and the entities of the old path are not `deleted`.
- The Rust source has the same gap (`populate_staged_contents` reads `HEAD:<new path>`). Task ^9f4rd5e ported it as is.

## Work

1. Copy `head_to_index.old_file.path` for a `GIT_STATUS_INDEX_RENAMED` entry in `LibGit2Status.swift`.
2. Give the old root-relative path of each rename through `GitStatus` (`GitStatusReader.swift`).
3. In the automatic mode, read HEAD at the old path and set `oldFilePath` of the `SemanticFileChange`.

## Tests

- A staged rename with no content change: no `added` change; the summary shows the entities as the same.
- A staged rename with a changed function: one `modified` (or `moved`) change, not `added`. #git