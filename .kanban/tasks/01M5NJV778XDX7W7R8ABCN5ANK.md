---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffce80
title: 'tools: guessed field names give a result''s main value (content/text/body/data, items/results/…)'
---
bench24-1023b, django__django-14238 (seq 8967): `tox.content.slice(0, 1500)` on a files.read result failed with "undefined is not an object". A read result now answers content, text, body, data with its untagged text; a list-shaped result answers items, results, entries, files, matches with its list. A real field of that name always wins. Tests: ForgivingCallsTests.aReadResultHasContent (exact snippet), aListResultAnswersEachListName. #bench