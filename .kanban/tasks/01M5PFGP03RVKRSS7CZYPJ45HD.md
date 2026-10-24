---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffdb80
title: git.show with no path shows the whole commit; sha/commit/rev name the ref; readText/get read a file
---
SWE-bench run bench24-1023b, django__django-14999.

1. seq 24055: `tools.git.show({ sha })` with no path failed "missing its required argument path". Make `path` optional; with no path, give the whole commit like `git show <sha>` (header, message, patch). Accept sha, commit, rev, revision as names of `ref`.
2. seq 23629: `tools.files.readFile` — add readText and get as files.read synonyms (readFile, cat, open, view already bound).
3. The `tools.name` placeholder hint was fixed at 0fd1d9b; pin the exact path-plus-options snippet with no hint text.

Tests: ShowCommitAndReadNamesTests.