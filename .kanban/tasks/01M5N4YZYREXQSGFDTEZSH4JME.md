---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc780
title: 'Forgiving: files.read result acts as its text; list-shaped results act as their array'
---
bench24-1023b django__django-13710 seq 668 (`py.slice` on a read result) and seq 879 (`glob2.slice`). A read result answers string methods, length, and template use on its plain text. glob/grep/list results answer array methods, length, indexing, and for-of on files/matches/entries. Each list entry also has `.name` (seq 1023 `e.name`). Test first: the exact snippets. #feature