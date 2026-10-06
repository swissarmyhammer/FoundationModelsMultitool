---
assignees:
- claude-code
depends_on:
- 01M48V80WKJ4QSW2TXPQ01E3QN
position_column: todo
position_ordinal: '8580'
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

- `swift build` and `swift test` pass with no new warnings. #git