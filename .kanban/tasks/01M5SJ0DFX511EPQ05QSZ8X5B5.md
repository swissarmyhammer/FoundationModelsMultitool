---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe180
title: enum arguments map common words (class → type, def → function) with a note
---
`code_context.searchSymbol({kind: "class"})` fails: argument "kind" must be one of "function", "method", "type", "other"; got "class" (14017 seq 6837). The check is in Multitool's ToolInvoker (generic enum guide), so fix it there for every verb with an enum.

Map in any letter case: class, struct, enum, interface, protocol, trait, record → type; func, fn, def → function (only when the target is in that enum). Also a plain case mismatch maps. Add a note to the result naming the mapping. Failing test first.