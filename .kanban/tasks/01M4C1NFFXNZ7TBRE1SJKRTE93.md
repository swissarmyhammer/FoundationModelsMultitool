---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c248hvbhehe02p727gp6n9
  text: |-
    Research:
    - `firstParentTree(of:)` and the path diff are `private` in `LibGit2Log.swift`. The new call needs the same first-parent tree diff. Plan: move the first-parent diff to `LibGit2Commit.swift` (the file for commit calls that more than one verb uses) as `firstParentDiff(of:limitedTo:)`, and call it from the log path filter and from `commitDetail`. Thus no copy.
    - libgit2 1.9 `git_patch_from_diff` gives a patch for a binary delta too (the header text is old). The patch is NULL only for a skipped delta, and a tree diff has none. The binary test reads `GIT_DIFF_FLAG_BINARY` on the patch delta.
    - `git_diff_find_similar` with NULL options reads `diff.renames` from the config. The call sets `GIT_DIFF_FIND_RENAMES` explicitly, thus the result does not depend on the host config.
    - `TemporaryGitRepository` cannot make a merge commit. The merge test uses `TestSupport.runGit` (checkout, commit, merge --no-ff) with `-c user.name/-c user.email`.
  timestamp: 2026-10-07T20:50:52.603952+00:00
- actor: claude-code
  id: 01m4c2qzy28nse46hc4t3w032w
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift (new), Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Commit.swift (the first-parent diff moved here as `firstParentDiff(of:limitedTo:)`), Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Log.swift (the path filter calls `firstParentDiff`), Tests/FoundationModelsMultitoolTests/LibGit2CommitDetailTests.swift (new). RED: the build failed on the missing `LibGit2FileStat` and `commitDetail`. GREEN: `swift test --filter LibGit2CommitDetailTests` 7/7 pass. `swift test` 2246 tests in 195 suites pass, 0 failures. The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from the mlx dependency bundle, not from this change.
    - next: /review
  timestamp: 2026-10-07T21:01:39.138012+00:00
- actor: claude-code
  id: 01m4c2wype4g6v0wt2jg99a7kk
  text: |-
    ### test — green
    - evidence: `swift test` — 2246 tests in 195 suites passed, 0 failed, 0 skipped. Project code gives 0 warnings.
    - note: one warning comes from a dependency (mlx-swift_Cmlx): "missing creator for mutated node". It is not ours.
    - next: review
  timestamp: 2026-10-07T21:04:21.710857+00:00
- actor: claude-code
  id: 01m4c36wmpp37z5b5wtqaf8ya7
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (5f922fc); 5 findings, 5 confirmed, 0 refuted — LibGit2CommitDetail.swift:52, :55, :58, :62, :66 (code-hygiene/dead-code-swift, assignOnlyProperty).
    - next: Remove the cause of each finding. The task stays in review.
  timestamp: 2026-10-07T21:09:47.286728+00:00
- actor: claude-code
  id: 01m4c37nvqtwmqa5mpb8amp94a
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files
    - test: green — swift test, 2246 passed
    - commit: 5f922fc
    - review: findings — LibGit2CommitDetail.swift:52, :55, :58, :62, :66 (code-hygiene/dead-code-swift, assignOnlyProperty)
  timestamp: 2026-10-07T21:10:13.111767+00:00
- actor: claude-code
  id: 01m4c3fygcm3n0des54p87mr03
  text: |-
    Fix for the 5 assignOnlyProperty findings:
    - Cause: no production code reads the five `LibGit2FileStat` fields yet. The tests read them only through whole-value `==` (the synthesized `Equatable` conformance), and periphery does not see that read. The reader in production is the `tools.git.commit` verb of ^0rtkdbt.
    - The rule `dead-code-swift` has a written contract for this case ("The staging contract", and "`assignOnlyProperty` and the reads periphery cannot see"). Do not delete the property. Write `// periphery:ignore` on the line above it, with the reason on its own comment line above the marker. The marker takes no text after it. I did this for all five properties. This is the same pattern as `SemanticFileChange.swift`.
    - I examined the full file. The fields of `LibGit2CommitDetail` (`facts`, `message`, `parentShas`, `files`) have direct reads in the tests, so they are not assign-only and need no marker.
    - I did not bring part of ^0rtkdbt forward, and I did not edit a validator.
  timestamp: 2026-10-07T21:14:44.108281+00:00
- actor: claude-code
  id: 01m4c3g12xhaf9va2hdtzt2a8h
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift (a reason comment and `// periphery:ignore` above each of `path`, `oldPath`, `status`, `additions`, `deletions`). `swift test`: 2246 tests in 195 suites passed, 0 failed. The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from the mlx dependency, not from this change. All 5 findings are checked.
    - next: /review
  timestamp: 2026-10-07T21:14:46.749366+00:00
- actor: claude-code
  id: 01m4c3jbdwtt2ad9rcgxbwh3ep
  text: |-
    ### test — green
    - evidence: swift test — 2246 tests in 195 suites passed, 0 failed, 0 skipped. Project code gives 0 warnings.
    - dependency warning (not ours): "missing creator for mutated node" for mlx-swift_Cmlx.bundle.
    - next: review
  timestamp: 2026-10-07T21:16:02.876644+00:00
- actor: claude-code
  id: 01m4c3r89ehcz7wkzgzq6nchh5
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 28b2580). 0 findings, 0 confirmed, 0 refuted. 7 validator runs attempted, 0 failed. 1 file reviewed. 2 `.kanban/` files are excluded by `.reviewignore`. All items in the prior Review Findings section are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-07T21:19:16.270711+00:00
- actor: claude-code
  id: 01m4c3rmvymdxry19att4ne128
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (periphery:ignore markers on LibGit2FileStat, per the dead-code-swift staging contract)
    - test: green — swift test, 2246 passed
    - commit: 28b2580
    - review: clean — 0 findings; task in done
  timestamp: 2026-10-07T21:19:29.150534+00:00
position_column: done
position_ordinal: ffffc380
title: 'git: read the full message and the per-file line counts of one commit in the LibGit2 layer'
---
## What

This is the first half of a new read-only verb `tools.git.commit`. The verb gives the facts of one commit, the same as the `git_show` tool of docker-agent (https://docker.github.io/docker-agent/tools/git/). This task adds only the `LibGit2` layer. The verb itself is in the next task.

At this time, `LibGit2Commit` (`Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2Commit.swift`) holds only `sha`, `author`, `date`, and `subject`. No call reads the full message or the changed files of one commit.

Make a new file `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift`. Follow the pattern of `LibGit2Changes.swift` and `LibGit2Commit.swift` (an `extension LibGit2Repository`, `throws(LibGit2Error)`, `LibGit2.makeHandle`):

- [x] Add a value type `LibGit2CommitDetail: Equatable, Sendable` with: `facts: LibGit2Commit`, `message: String` (the full message, `git_commit_message`), `parentShas: [String]`, and `files: [LibGit2FileStat]`.
- [x] Add `LibGit2FileStat: Equatable, Sendable` with `path: String` (the new path), `oldPath: String?` (only for a rename), `status: String` (`added`, `modified`, `deleted`, `renamed`), `additions: Int?`, `deletions: Int?` (`nil` for a binary file).
- [x] Add `func commitDetail(forRevision revision: String) throws(LibGit2Error) -> LibGit2CommitDetail?`. Use `commit(forRevision:)` to find the commit (`nil` when no object has that name). Diff the tree of the first parent to the tree of the commit with `git_diff_tree_to_tree`. For a root commit, use a `nil` old tree. Find renames with `git_diff_find_similar`. Get the counts with `git_patch_from_diff` and `git_patch_line_stats`.
- [x] Keep the files in the order that the diff gives them.

## Acceptance Criteria

- [x] `commitDetail(forRevision:)` gives the full message, with the body after the subject, for a commit that has a body.
- [x] For a normal commit, each changed file has the correct `status`, `additions`, and `deletions`.
- [x] A root commit lists each of its files as `added`.
- [x] A merge commit uses only its first parent for the diff.
- [x] A rename gives `status == "renamed"` and the old path in `oldPath`.
- [x] A binary file gives `nil` for `additions` and `deletions`.
- [x] An unknown revision gives `nil` and does not throw.

## Tests

- [x] Make `Tests/FoundationModelsMultitoolTests/LibGit2CommitDetailTests.swift`. Use `TemporaryGitRepository` and `GitTestHistory` (`Tests/FoundationModelsMultitoolTests/GitTestHistory.swift`) or `TestSupport.runGit` to make the history. Write one test for each acceptance criterion above.
- [x] Run `swift test --filter LibGit2CommitDetailTests`. All tests must pass. Then run `swift test`. The full suite must pass with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 16:04)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 8 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift:52` `code-hygiene/dead-code-swift` — var.instance `path` is assignOnlyProperty.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift:55` `code-hygiene/dead-code-swift` — var.instance `oldPath` is assignOnlyProperty.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift:58` `code-hygiene/dead-code-swift` — var.instance `status` is assignOnlyProperty.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift:62` `code-hygiene/dead-code-swift` — var.instance `additions` is assignOnlyProperty.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/LibGit2/LibGit2CommitDetail.swift:66` `code-hygiene/dead-code-swift` — var.instance `deletions` is assignOnlyProperty. #git