---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4g9v7jdzx18qak1exejwmfw
  text: |-
    Research and RED done.
    - Defect 1 cause: `Changes.changes(for:status:in:)` takes `arguments.branch ?? repository.currentBranchName()` and gives the correction when the result is nil, before it reads the range. `currentBranchName()` gives nil for a detached HEAD AND for a repository with no commit, so the two cases were the same. The old test "a detached HEAD with no branch argument is a correction" pinned that contract; the card changes it, so that test is replaced.
    - Defect 2 cause (checked, not guessed): the `@HEAD` side is correct. `LibGit2Repository.blob(atPath:revision:)` reads the commit tree with `git_object_lookup_bypath`. The cause is in the semantic engine: `SemanticDiffer` compares only entities (functions, classes, keys). A line that no entity covers (a trailing comment, an import, a top-level statement) is in no entity, so its change is in no content hash and the diff gives 0 changes. The Rust source `parser/differ.rs` has the same gap. This is true for every plugin that leaves lines outside its entities (code, JSON, YAML, TOML, Markdown, Vue); the fallback plugin covers each line.
    - RED: new tests fail as expected: GitChangesTests (detached HEAD with no argument, clean tree, three ranges) and GitDiffTests (comment added at end / removed from end, for .py, .swift, .ts, .rs).
    - Plan for defect 2: keep `computeSemanticDiff` parity with Rust by default (the golden tests call it), add an opt-in that also compares the lines no entity covers, with `LineDiff`, and gives one change of kind `lines` for each changed run of lines. A run of blank lines only is no change. `Diff` turns the opt-in on for all three modes.
  timestamp: 2026-10-09T12:22:43.021024+00:00
- actor: claude-code
  id: 01m4gatfzzswzg9s18an2c9rcq
  text: |-
    Implementation landed (not committed).
    - Defect 1: new `LibGit2Repository.isHeadDetached()` (`git_repository_head_detached`). `Changes.branchTarget(named:in:)` reads the branch argument, else the branch of HEAD, else `HEAD` itself (no parent) for a detached HEAD. Only a repository with no commit stays a correction (new text: "HEAD names no commit ..."). The result `branch` is `HEAD` on a detached HEAD.
    - Defect 2: new `Semantic/UncoveredLines.swift`. `SemanticDiffer.computeSemanticDiff` takes `reportsUncoveredLines` (default `false`, so the Rust goldens do not change); `Diff.semanticDiff` passes `true` for all three modes. Each changed run of lines that no entity holds is one change, entityType `lines`, name `lines <first>-<last>` (shared with the fallback plugin through `SemanticEntity.lineSpanName`). Blank-only runs are no change.
    - What did not work: the first version aligned only the lines outside entities. That joined two runs that an entity separates (a comment removed above a function and a comment added below it became one `modified` run). `UncoveredLinesTests` caught it. The fix keeps one marker piece for each block of entity lines in the alignment, so a run cannot cross an entity.
    - Discovery: the build prints "warning: missing creator for mutated node ... mlx-swift_Cmlx.bundle". It is a build-system warning from a dependency and was there before the first edit.
    - Docs: README.md (git section) and git.md decision 6 describe both changes.
  timestamp: 2026-10-09T12:39:47.455165+00:00
- actor: claude-code
  id: 01m4gatjt22gk85qwch9my1tvg
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the pre-existing mlx build-system warning); `swift test` 2339 tests in 206 suites passed. Files: Sources/.../Git/Changes.swift, Git/Diff.swift, Git/LibGit2/LibGit2Branches.swift, Git/Semantic/UncoveredLines.swift (new), Git/Semantic/SemanticDiffer.swift, Git/Semantic/SemanticEntity.swift, Git/Semantic/FallbackParserPlugin.swift; Tests/.../GitChangesTests.swift, GitDiffTests.swift, LibGit2BranchesTests.swift, UncoveredLinesTests.swift (new); README.md, git.md.
    - next: /review. After the commit is on origin/main, send the commit to the session foundationmodelsacpagent-fd (card Workflow).
  timestamp: 2026-10-09T12:39:50.338230+00:00
- actor: claude-code
  id: 01m4gc0g4eqmxd1t9k5f9wqp64
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (ea0d60f): 0 findings, 0 confirmed, 1 refuted; 12 files reviewed. The .kanban files are excluded by .reviewignore. No validator matches README.md and git.md. The commit renames no file.
    - next: none. The task is in done.
  timestamp: 2026-10-09T13:00:32.782302+00:00
- actor: claude-code
  id: 01m4gc0wsq3f1dsmdm5kgxbk36
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 13 files (Changes.swift, Diff.swift, LibGit2Branches.swift, new UncoveredLines.swift, semantic differ files, tests, README.md, git.md)
    - test: green — swift test, 2339 passed (race fix in SuspendedContextTests)
    - commit: ea0d60f
    - review: clean — 0 findings; task in done
    - next: after the push to origin/main, send the commit to the session foundationmodelsacpagent-fd
  timestamp: 2026-10-09T13:00:45.751355+00:00
position_column: done
position_ordinal: ffffd280
title: tools.git.changes fails on a detached HEAD, and tools.git.diff misses a change against HEAD
---
## What
Two defects in `tools.git`, found by FoundationModelsACPAgent (its task ^fts1r32) on a SWE-bench clone. The agent mounts the git tools by default, and the SWE-bench runs use them.

Setup: Multitool 24f65ed; the git verbs are the same on origin/main c8c74ba. The repository is a full django clone with a detached HEAD at base commit 0456d3e427 (`git checkout --force <sha>`).

### 1. `tools.git.changes` cannot work on a detached HEAD
- `tools.git.changes({})` and `tools.git.changes({range: "HEAD"})` both give the correction "HEAD names no branch: HEAD is detached, or the git repository has no commit. Give branch to name the local branch to read."
- The branch check comes before the range is read, so a range cannot help.
- `branch: "main"` then reads the upstream history after the base commit, which is wrong for this case.
- Expected: on a detached HEAD, `changes` uses HEAD (or the given `range`) and needs no branch name. The correction stays only for a repository with no commit.

### 2. `tools.git.diff` misses a change against HEAD
- `tools.git.diff({left: "django/contrib/admin/sites.py@HEAD", right: "django/contrib/admin/sites.py"})` gave 0 changes for a comment line that was added at the end of the file.
- `git diff <base>` shows that change.
- Expected: the diff shows each changed line, including a comment line at the end of the file. Find the cause (for example: a semantic diff that ignores comments or trailing trivia, or the `@HEAD` side read from the working tree) and fix it for every language, not only Python.

## Acceptance Criteria
- [x] `changes({})` on a detached HEAD lists the changes from HEAD with no branch argument and no correction.
- [x] `changes({range: "HEAD"})` (and another range) on a detached HEAD works the same way.
- [x] `diff` of `<path>@HEAD` against the working-tree `<path>` reports a comment line added at the end of a file.
- [x] The diff still reports every other kind of change it reports today.

## Tests
- [x] A test repository with a detached HEAD (made in a temporary directory) for `changes` with no argument and with a range.
- [x] A test that adds a comment line at the end of a tracked file and calls `diff` against `@HEAD`; cover Python and at least one other language.
- [x] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- When the fix is on origin/main, send the commit to the session foundationmodelsacpagent-fd, so that the agent can move its pin.