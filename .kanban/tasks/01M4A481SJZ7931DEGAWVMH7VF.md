---
assignees:
- claude-code
position_column: todo
position_ordinal: 8f80
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