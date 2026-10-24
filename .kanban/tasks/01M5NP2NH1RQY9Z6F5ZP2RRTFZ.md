---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd080
title: 'runCode: a snippet that is plainly Python runs with python3 through shell.execute'
---
bench24-1023b, django__django-14382 (child seq 11129): a Python snippet (`import os`, `for t in [...]:`, `return results`) failed with "Unexpected identifier 'os'". When a snippet does not parse as JS, the repair finds nothing, it has a Python-only line and no JS mark (const/let/var/await/function/=>/tools./trailing ';'), and the surface has shell.execute, it runs as one tools.shell.execute call: the body is wrapped in a function, run with .venv/bin/python or python3 in the shell root, and the return value printed as JSON (repr fallback). The result carries the note "This snippet was Python; it ran with python3." A failure returns the output and traceback. Test: PythonSnippetTests. #bench