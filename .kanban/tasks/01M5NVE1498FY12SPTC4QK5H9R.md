---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd480
title: 'tools: the not-an-object error names the real verb, never tools.name'
---
bench24-1023b, django__django-14534: "Tool call arguments must be a JS object (`tools.name({ … })`)". The unknown-tool hint read `tools.name` as the path the model called and suggested code_context.getRenameEdits. The message now shows `tools.<real path>({ <main arg>: … })`, and the generic form names no path. Test: ShellResultAndPositionalTests.aNonObjectCallNamesTheRealVerb. #bench