---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe380
title: shell.execute workingDirectory equal to the root's own folder name uses the root
---
`workingDirectory: "repo"` where the root is `.../repo` resolves to `.../repo/repo` and fails "Failed to set working directory" (14534 seq 11936).

When a relative directory does not exist and equals the last folder name of the root, use the root and add a note to the result. Fix in ShellRunner.effectiveWorkingDirectory / Execute. Failing test first.