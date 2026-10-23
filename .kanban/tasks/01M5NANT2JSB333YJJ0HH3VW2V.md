---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffcb80
title: 'Forgiving: repair a snippet that does not parse when exactly one small repair makes it parse'
---
bench24-1023b django__django-13964 child seq 4702: `{ pattern "unsaved", ... }` (missing ':') failed a whole snippet of three grepCode calls. When a run fails and the snippet does not parse (so nothing ran), try: a missing ':' after an identifier property name; a missing ',' at the end of a line before another property/item; an extra or missing ')' '}' ']' at the end. Run the repaired code only when exactly one candidate parses, and close the result with "Repaired: …". Test first: the exact snippet. #feature