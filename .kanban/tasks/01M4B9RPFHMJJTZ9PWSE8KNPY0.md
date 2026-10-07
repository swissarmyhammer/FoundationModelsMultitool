---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: 'git: the git.show description names tools.files.read, also when no files capability is mounted'
---
## Problem

The description of `tools.git.show` says: "Omit ref to read the file at HEAD; tools.files.read reads the file in the work folder instead." A host can mount git alone (`MultiTool.Builder().withGit(root:)`). Then `tools.files.read` does not exist.

## Evidence

Local integration run, 2026-10-07 (task ^k6wzrxn): with the prompt "compare Sources/Geometry.swift at HEAD with the file in the work folder", the model searched for a file reader four times, then called `tools.files.read` (the snippet failed: "tools.files.read does not exist"), and called `git.diff` only after 8 tool calls. The turn took 171 s instead of approximately 27 s.

## Work

- Make the description of `git.show` name only verbs that the mount has, or name `git.diff` (a path with no ref reads the work folder) for the work-folder side.
- Add a unit test that the description of each git verb names no tool path outside the git mount when git is mounted alone. #git