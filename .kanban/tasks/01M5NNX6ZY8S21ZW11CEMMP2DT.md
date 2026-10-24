---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffcf80
title: 'tools: a made-up verb name that holds a read verb calls it (files.listEntries → files.list)'
---
bench24-1023b, django__django-14382 (root seq 10955): `tools.files.listDir({ path: "tests" })` was "not a function" (fixed by 95a7741 for listDir; lsDir, listFolder, listEntries still failed). Add lsdir and listfolder to the files.list synonyms. A group name holding exactly one read verb's name or synonym of 4+ letters (longest wins, must be one path) now calls it — only files.read/list/glob/grep, so a name like deleteAllFiles never runs anything. Test: ContainedVerbCallTests. #bench