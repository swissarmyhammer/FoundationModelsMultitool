---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
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