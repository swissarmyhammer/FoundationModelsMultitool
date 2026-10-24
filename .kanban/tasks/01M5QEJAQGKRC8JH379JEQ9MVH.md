---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffdf80
title: Forgive a list result read as one item; name an empty list in the error (noqueue24)
---
From SWE-bench run noqueue24, reported by foundationmodelsacpagent-83.

1. django__django-13447 seq 212: `trim(s1)` reads `s.file`, `s.startLine` and `s.text.slice(...)` off a whole `getSymbol` result `{ query, symbols }`. Fix: a list result answers a field it does not have from its first item, through the item aliases. An item answers `source`, `code`, `body` and `snippet` for its `text`.
2. django__django-13710 seq 1351: `grep.matches[0].startLine` on a `grepCode` that matched nothing. `ForeignObjectRel` is in reverse_related.py, so the list was empty and the shape was right. Fix: `EmptyListHint` names the `[0]` expression and says the list is empty.

Tests: SymbolResultReadAsItemTests (both snippets exact) and EmptyListHintTests.