---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffcd80
title: 'runCode: "(line N)" of a snippet error counts the snippet''s own lines'
---
bench24-1023b: snippet errors carried lines 113–124 for snippets of 1–5 lines (e.g. "(line 116)" where the bad line was 2, django__django-14017 seq 7751): the line counted the preamble. Map the line back through wrappingSnippet for parse and runtime errors alike; a line in the preamble or the closing line is left out. Test: SnippetErrorLineTests (parse error and null-deref on line 2 of 3 report line 2). #bench