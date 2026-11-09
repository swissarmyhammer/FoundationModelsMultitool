---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'B: shell.getLines resolves a runCode completion token to the commands it started'
---
dotask24 13447 seq 661/689, kanban24 13925 seq 2749/2753: getLines(token of pending snippet) → "No command of this session ran under the completion token". Resolve snippet token to its command(s). #forgive