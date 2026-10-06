---
assignees:
- claude-code
depends_on:
- 01M48V80WKJ4QSW2TXPQ01E3QN
position_column: todo
position_ordinal: '8280'
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