---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc480
title: 'files.list: list a directory''s entries ({path} → entries)'
---
From SWE-bench run bench24-1023 (django__django-13710 seq 1023): `tools.files.list({ path: "django/utils" })` was "not a function". There is no directory-listing verb today (glob needs a pattern and answers files only), so add `tools.files.list`: optional `path` (default: session root), answers the immediate entries sorted by name, a directory with a trailing `/`, bounded by the PathGuard, honoring the host exclude patterns; a bad / missing / non-directory path is a correction. Existing verbs stay.

Test first: a snippet `tools.files.list({path})` through MultiTool lists a dir.

#feature