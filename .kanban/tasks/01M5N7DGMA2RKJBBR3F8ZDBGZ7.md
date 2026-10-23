---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc980
title: 'Forgiving: a standby runCode snippet while background work runs ends the answer'
---
bench24-1023b django__django-13925 child session seq 2837–3247: `return "standby"` sent 28 times in 2 minutes while a background command ran. A depth-0 snippet that calls no tools.* and only returns a constant (or nothing), while the session has another background run open, answers a text that says to end the answer and invites no new call. Ending the answer itself belongs to Router (no tool-side API). Test first: the exact snippet with a scripted pending run. #feature