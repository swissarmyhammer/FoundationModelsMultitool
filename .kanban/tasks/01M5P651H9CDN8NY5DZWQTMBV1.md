---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd880
title: An item with only an LSP range answers line, startLine, endLine
---
Follow-up to be4385f: references/implementations/definitions carry an LSP `range` and no `startLine`, so `r.line` was undefined. Checked: LSP Position.line, grepCode startLine/endLine (tree-sitter chunk rows), and listSymbol/getSymbol startLine/endLine are all zero-based, so range.start.line / range.end.line pass through unchanged as line/startLine/endLine. Real fields win. files.grep `line` stays 1-based. Test: CodeContextListResultTests.aRangeAnswersItsLines.