---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m49011z6qd58ve7hajqhck4e
  text: |-
    Research (before code):
    - `blame` is the first verb of `GitCapability` (`tools` is empty in the base; `GitCapabilityTests.theCapabilityOwnsTheGitNounAndHoldsNoVerbYet` asserts that, and must change).
    - Rust `blame_lines`: (1) 0 lines -> empty; (2) path in neither the index nor the HEAD tree -> `Untracked` for each line; (3) `blame_file` with `GIT_ENOTFOUND` (staged new file, or no commit yet) -> `Worktree` for each line; (4) `blame_buffer(base, content)` -> zero final oid = `Worktree`, else `Commit(sha)`; a line with no hunk -> `Worktree`. Other errors -> `Failed` (here: one `correction`).
    - libgit2 1.9 `git_blame_buffer` makes the new hunks with a zero `final_commit_id` and a NULL `final_signature` (blame.c `buffer_line_cb`). Thus the layer reads the author only for a non-zero oid.
    - Line model: libgit2 counts lines by `\n`. `Hashline.splitLines` also splits on a bare `\r`, thus the count can differ. `GitPatch.lines(of:)` (private) is the git line model; plan: make it internal and reuse it, not a copy.
    - `LibGit2Repository.handle` is private; the blame functions go in a new file of the `LibGit2` layer, thus `handle` becomes internal (the layer only).
    - Path flow: `PathGuard.validate(_:for: .read)` gives a canonical URL; a new `GitRepositoryLocation.repositoryPath(ofFile:)` changes it to the work-folder path (realpath, git.md fact 1). The result `path` is root-relative.
    - Rules dump read (swift set): no force unwrap/print in sources, name each number except 0/1/-1/100, doc every declaration, function body <= 250 lines, synthesized initializers, enum for the line state.
  timestamp: 2026-10-06T16:16:27.110832+00:00
- actor: claude-code
  id: 01m490mepfhw4taeryrjb35hch
  text: |-
    Implementation landed (TDD: RED was the compile failure for the missing `stage`, `repositoryPath(ofFile:)`, `blameLines`, `Blame` types; then 4 real test failures, all fixed in the code, not in the expectations).

    Discoveries (what did not work first):
    - `git_blame_buffer` SPLITS a base hunk around a changed line (`split_hunk_in_vector` in blame.c). The second part keeps the commit id but has a NULL `final_signature`. The first version read the author from the hunk and called a NULL signature "uncommitted": line 3 after a dirty line 2 came back uncommitted. Fix: decide by the oid only (the same as Rust), and read author and date from the commit (`git_commit_lookup` + `git_commit_author`), one lookup per sha (cache).
    - A staged file in a repository with NO commit: `git_blame_file` fails with the generic code -1 ("reference 'refs/heads/main' not found"), not `GIT_ENOTFOUND`. Rust would give `Failed` there (git2 maps -1 to GenericError), but its doc says a tracked file with no reachable commit is "not yet blamable" -> Worktree. The layer checks `git_repository_head_unborn` first and gives `uncommitted`, which keeps the documented contract.
    - `PathGuard` refuses `../b.txt` with "Path contains blocked pattern '../'", before the boundary check. The outside-root test now compares the verb correction with the refusal of `context.pathGuard` itself.
    - A second `withGit(root:)` now fails with `.duplicateName` "blame" (verbs collide path by path), not `.duplicateNoun`, the same as a second `withFiles`. The test changed to that.

    Decisions inside the card:
    - Result: `path` (root-relative), `lines` [{`line`, `sha?`, `author?`, `date?` (ISO 8601 UTC), `text`, `state`}], `capped: Bool` (the cap report), `correction?`. `author` and `date` are nil when `sha` is nil (uncommitted/untracked rows have no commit).
    - Cap: `Blame.lineCap = 1000` rows; `capped` is true when the range is longer. A `startLine`/`endLine` past the end is a correction that names the line count; `startLine > endLine` is a correction; bounds 1...1_000_000 through `BoundParameter` (same range as `ReadArguments.offsetRange`).
    - `GitPatch.Line` and `GitPatch.lines(of:)` changed from private to internal, for reuse of the git line model. `LibGit2Repository.handle` changed from private to internal (LibGit2 layer only). `TemporaryGitRepository` gained `stage(_:)` and a shared `withIndex` helper.
  timestamp: 2026-10-06T16:27:02.735402+00:00
- actor: claude-code
  id: 01m490mmw1ehtap32ehbndhk9k
  text: |-
    ### implement — changed
    - evidence: 12 files. New: Sources/FoundationModelsMultitool/Capabilities/Git/Blame.swift, Capabilities/Git/LibGit2/LibGit2Blame.swift, Tests/FoundationModelsMultitoolTests/GitBlameTests.swift, Tests/FoundationModelsMultitoolTests/LibGit2BlameTests.swift. Changed: Capabilities/Git/GitCapability.swift (tools = [Blame]), Capabilities/Git/GitRepositoryLocation.swift (repositoryPath(ofFile:)), Capabilities/Git/LibGit2/LibGit2Repository.swift (handle internal), Capabilities/Files/GitPatch.swift (Line, lines(of:) internal), Tests/Support/MultitoolTestSupport/TemporaryGitRepository.swift (stage, withIndex), Tests/.../GitCapabilityTests.swift, GitContextTests.swift, TemporaryGitRepositoryTests.swift. `swift package update` OK. `swift build --build-tests`: 0 errors, 0 warnings from this repo (only the known mlx-swift "missing creator for mutated node"). `swift test`: 1904 tests in 161 suites pass (was 1881 in 159). IntegrationTests `swift build --build-tests`: Build complete, same known warning only.
    - next: /review. The task stays in `doing`.
  timestamp: 2026-10-06T16:27:09.057523+00:00
- actor: claude-code
  id: 01m490r0gnwndfnfvgm40er9y0
  text: |-
    ### test - green
    - evidence: swift build --build-tests OK. swift test: 1904 tests in 161 suites passed, 0 failed. IntegrationTests swift build --build-tests OK.
    - warnings: only "missing creator for mutated node" for mlx-swift_Cmlx.bundle. This is a dependency warning from before this change. It is not red.
    - next: review
  timestamp: 2026-10-06T16:28:59.285835+00:00
- actor: claude-code
  id: 01m490rde7s5wzzd1gc0zq9x6s
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add git blame to the git capability" with all working tree changes (Blame.swift, LibGit2Blame.swift, two test suites, Git and GitPatch changes, test support, .kanban). The sha is in the final report of this step.
    - next: review
  timestamp: 2026-10-06T16:29:12.519314+00:00
- actor: claude-code
  id: 01m4915xtrjq1g9h39tk7tc9qr
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit a5280f6); 1 finding, 1 confirmed, 0 refuted; 12 files reviewed, 4 .kanban files not reviewed (.reviewignore); no renamed file. Sources/FoundationModelsMultitool/Capabilities/Git/Blame.swift:119 (swift/naming-clarity: rename `capped` to `isCapped`).
    - next: implement the open item in the 2026-10-06 11:29 Review Findings section, then review again.
  timestamp: 2026-10-06T16:36:35.288168+00:00
- actor: claude-code
  id: 01m4916d8n4njjc2hs8q144aap
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files (Blame.swift, LibGit2Blame.swift, 2 new test suites, 8 changed)
    - test: green — swift test, 1904 passed in 161 suites; IntegrationTests build complete
    - commit: a5280f6
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Git/Blame.swift:119 (swift/naming-clarity: `capped` -> `isCapped`)
  timestamp: 2026-10-06T16:36:51.093752+00:00
- actor: claude-code
  id: 01m491c55jrqs0fbt70dn97wxk
  text: |-
    Finding work (swift/naming-clarity, Blame.swift:119): `BlameResult.capped` is now `BlameResult.isCapped`.
    - Whole-file scan: in Blame.swift, `capped` was the only Boolean member with a bare adjective. In LibGit2Blame.swift, the Boolean members are `isTracked`, `isInIndex`, `isInHeadTree`; they already read as assertions. `libGit2True` is an `Int32` constant, not a Boolean.
    - Changed uses: the property, the two `BlameResult(...)` initializer calls, the doc comment of `lineCap`, the doc comment of `Blame`, and the `description` text that the model reads ("when isCapped is true"). The model-facing field name is the property name of the `@Generable` result, thus the description must name `isCapped`.
    - Tests: GitBlameTests (three assertions and one doc comment). LibGit2BlameTests had no `capped` use.
    - Out of scope, not changed: `GlobResult.capped` and the files capability.
    - Discovery: the sah `edit file` op with `replace_all: true` changed only the first of three sites. Check `replacements_made` after a `replace_all` edit.
    - TDD: RED was the compile failure "value of type 'BlameResult' has no member 'isCapped'" at three test sites. GREEN: the two blame suites, 19 tests in 2 suites pass.
  timestamp: 2026-10-06T16:39:59.410211+00:00
- actor: claude-code
  id: 01m491c7he8ac5ss314vhnasdf
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Git/Blame.swift, Tests/FoundationModelsMultitoolTests/GitBlameTests.swift. `swift build --build-tests`: Build complete, 0 errors, only the known mlx-swift "missing creator for mutated node" warning. `swift test`: 1904 tests in 161 suites passed, 0 failed. Finding Blame.swift:119 is `- [x]`.
    - next: /review. The task stays in `doing`.
  timestamp: 2026-10-06T16:40:01.838273+00:00
- actor: claude-code
  id: 01m491fgaf340t65p1985dtape
  text: |-
    ### test - green
    - evidence: swift build --build-tests - complete. swift test - 1904 tests in 161 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests - complete.
    - warnings: only one warning in each build, "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It is a known dependency warning from before this change. It is not counted as red.
    - next: review
  timestamp: 2026-10-06T16:41:49.135981+00:00
- actor: claude-code
  id: 01m491g21aga4pnf4wz5yz36kt
  text: |-
    ### commit — changed
    - evidence: one local commit "refactor: rename capped to isCapped in git blame" with Blame.swift, GitBlameTests.swift and the .kanban changes. The sha is in the git log. Not pushed.
    - next: review
  timestamp: 2026-10-06T16:42:07.274464+00:00
depends_on:
- 01M48V80WKJ4QSW2TXPQ01E3QN
position_column: doing
position_ordinal: '80'
title: 'git: tools.git.blame'
---
## Goal

Add the `blame` read verb (git.md, "Verbs").

## Source

- `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`: `blame_lines` (line 1037) and `LineBlame` (near line 50). `LineBlame` has three kinds: a real commit, a line in the working tree that is not committed, and a failed blame.

## Work

1. `Blame` verb (`name = "blame"`). Arguments: `path: String`, `startLine: Int?`, `endLine: Int?` (1-based, both included; default: the whole file).
2. Result: `path`, `lines` (each: `line`, `sha` or nil, `author`, `date`, `text`, and a `state` of `committed`, `uncommitted`, or `untracked`), `correction: String?`.
3. Keep the behavior of `blame_lines` for a file with uncommitted changes and for an untracked file. A failed blame is one `correction`, not a throw.
4. Keep a line cap; report when it cut the result.
5. The path goes through the `PathGuard` of `GitContext`.
6. Add the verb to `GitCapability.tools`.

## Tests

- A file with lines from two commits.
- A line range.
- A file with an uncommitted change; an untracked file.
- A bad range (start after end, past the end): a correction.
- A path outside the root: a correction.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.

## Review Findings (2026-10-06 11:29)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Blame.swift:119` `swift/naming-clarity` — Boolean property uses bare adjective instead of `is` prefix. Non-mutating Boolean members should read as assertions using the `is`/`has` prefix pattern per Swift naming conventions. `capped` is a bare adjective like the discouraged `empty`/`enabled`. Rename `capped` to `isCapped` to match Swift naming conventions for boolean properties. #git