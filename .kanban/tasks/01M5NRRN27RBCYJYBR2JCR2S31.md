---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd180
title: 'tools: other names of code_context read verbs call them (code_context.search → searchSymbol)'
---
bench24-1023b, django__django-14411 (root seq 12018): `tools.code_context.search({query})` was "not a function". Add VerbSynonyms rows for the code_context read verbs (searchSymbol, getDefinition, getReferences, getInboundCalls, listSymbol, grepCode, getCallgraph, getBlastradius). A name may now mean a verb in more than one group (search: files.grep and code_context.searchSymbol), and it resolves in the group it is called in. The contained-verb rule covers the code_context read verbs, but not rebuildIndex or the LSP verbs. The hint prefers the called group and falls back to any group. Test: CodeContextSynonymTests. #bench