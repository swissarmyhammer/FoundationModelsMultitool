---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: 'H: no-progress timeout must not stop a silent live test run; a pending command that ends must reach the model'
---
dotask24 13964 coder seq 4000, 14016 seq 4945: "runCode timed out after 120.0 seconds with no progress" exitCode -1 on full Django suite. 13964 coder seq 4357-4366 never saw that result. Investigate both. #forgive