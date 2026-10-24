---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd380
title: 'tools: a main string argument then an options object merge (files.read("…", { offset, limit }))'
---
bench24-1023b, django__django-14534 (root seq 13418): `tools.files.read("tests/…/test_forms.py", { offset: 670, limit: 70 })`. Since 95a7741 this silently dropped the options and read the whole file. Now { <main arg>: first, ...second }, the object wins on a clash. It applies to every verb with one main string argument. Test: ShellResultAndPositionalTests.aPathAndOptionsAreMerged. #bench