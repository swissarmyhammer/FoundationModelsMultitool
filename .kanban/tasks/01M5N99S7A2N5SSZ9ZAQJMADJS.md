---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffca80
title: 'files.delete: delete one file (or, with directory: true, an empty dir); delete synonyms callable'
---
bench24-1023b django__django-13933 seq 4183: `tools.files.delete({ path })` was "not a function"; the failure took the snippet's test run down too, and seq 4186 ran it again. Add the verb: bounded by PathGuard, refuses .git internals, the host exclude patterns and a read-only session; a missing path is a correction; records a delete change. Synonyms remove/rm/unlink/del/deleteFile/erase → files.delete; rmdir → files.removeDirectory (empty-only by default), now callable. The hint for a delete-like name names files.delete. Test first: the exact snippet. #feature