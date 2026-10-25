---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe080
title: shell.execute result `output` acts as a string
---
Model writes `r.output.trim()` / `r.output.split("\n")`; fails "out(ps).trim is not a function" (14672 seq 16829), "r1.output.split is not a function" (14752 seq 18454). Model then re-runs tests.

Make `output` on a shell.execute result (forgiving bindings, `asShell`) an array that also has the String methods (trim, split, includes, match, slice, …) over the joined text (without the `N: ` prefixes). Array methods keep working. Failing test first.