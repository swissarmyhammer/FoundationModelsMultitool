---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc580
title: 'Forgiving: argument synonyms (file/filePath/dir… → path, query/regex → pattern)'
---
bench24-1023 django__django-13447 seq 469: `tools.files.read({ file: "…" })` → missing required argument "path". ToolInvoker renames a known synonym or a case/underscore variant of a schema property when the property is absent and the meaning is unique. Test first: the exact snippet. #feature