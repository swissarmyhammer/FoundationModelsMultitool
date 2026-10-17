---
assignees:
- claude-code
depends_on:
- 01M53W3412PXE4RG6PPSF7H4GS
position_column: todo
position_ordinal: '9480'
title: 'T1 group 6: temp folders and other test fixture leaks'
---
Split from ^nvxckvr (test rule T1). The list (temp folders, files and other fixtures that are removed only on the success path) is in the comments of ^nvxckvr.

Rule T1: fixtures close also when the test body throws.

Do: remove each temp folder and close each other fixture on both paths (defer for synchronous removal; an awaited helper for async close). Use one shared temp-folder helper if the same code repeats. Keep the checks of each test the same.

No .timeLimit, sleep, poll or retry. Do not delete a test. Do not change production code only to add a test hook. One full run. #elicitation-fixes #t1