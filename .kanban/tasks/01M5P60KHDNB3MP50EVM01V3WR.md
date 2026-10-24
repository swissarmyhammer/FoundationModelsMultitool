---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd780
title: Each list-shaped code_context result acts as its list
---
bench24-1023b django__django-14752 seq 19079: `refs.map(...)` on a code_context.grepCode result threw "refs.map is not a function" (a run from before 15ae895, which shaped grepCode). Fix: resultShapes for every list-shaped code_context verb with its real FoundationModelsCodeContext field: searchCode → hits, searchSymbol → symbols (a bare list already), getReferences → references, getImplementations → implementations, getInboundCalls → calls, getDefinition/getTypeDefinition → locations. Each item of any shaped list answers file/filePath/path and line/startLine/lineNumber. Test: CodeContextListResultTests with the run's snippet.