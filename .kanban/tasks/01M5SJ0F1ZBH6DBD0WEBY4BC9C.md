---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe280
title: files.search / files.grep items answer `lines`
---
`res.files.map(f => f.lines.map(l => ...))` fails "undefined is not an object (evaluating 'f.lines.map')" (14411 seq 10826). files.search → files.grep.

Give each match item a `lines` list of `{ number, line, text }` that the model expects (aliased to the item's own line/text) in the forgiving bindings. Failing test first.