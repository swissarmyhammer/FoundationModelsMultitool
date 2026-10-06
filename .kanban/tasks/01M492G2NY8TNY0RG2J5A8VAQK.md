---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
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