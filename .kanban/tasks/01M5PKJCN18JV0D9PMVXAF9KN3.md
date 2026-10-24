---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffdc80
title: code_context lines are 1-based at the tool surface (CodeContext 223732b)
---
FoundationModelsCodeContext 223732b makes every code_context line and column 1-based, in and out. Multitool does no arithmetic between bases; the range→line/startLine/endLine mapping passes values through. Update the ForgivingBindings comment and CodeContextListResultTests to the 1-based convention, the same as files.grep and files.read.