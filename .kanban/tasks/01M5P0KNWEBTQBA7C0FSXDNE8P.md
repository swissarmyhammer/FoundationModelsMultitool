---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd580
title: A null list field reads as [], and grep matches answer each other's field names
---
bench24-1023b django__django-14608 seq 15808: files.grep with no match (or a missing path) gave `matches: null`, so `r2.matches.map(...)` threw "null is not an object" and the good grepCode call was lost. Fix: in the forgiving bindings, a null/undefined list field of a list-shaped result reads as [] (the correction stays); each match of files.grep / code_context.grepCode answers file/filePath/path and line/startLine/lineNumber. Test: EmptyListResultTests with the run's snippet.