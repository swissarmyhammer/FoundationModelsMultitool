---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffda80
title: shell.command runs shell.execute; shell.run guarded by a test
---
bench24-1023b django__django-14915 seq 21437: `tools.shell.run({ command: "git log ..." })` → "is not a function". run/exec/sh/bash/runcommand already bind since 95a7741 (the bench build predates it); `command` was missing. Added `command` to the shell.execute row. Test: ShellVerbSynonymTests with the run's exact call and each name.