---
assignees:
- claude-code
depends_on:
- 01M53FFTWPSZVY0DTYKZJDTDFJ
position_column: todo
position_ordinal: '8280'
title: 'Rule R4, group B: each decline or cancel that Multitool makes carries _meta.reason on the MCP wire'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), rule R4, group B.

Each decline or cancel that Multitool makes itself must carry `_meta.reason` on the MCP wire. Today these have no reason:
- MCPServer+Elicitation.swift about line 122: a schema outside the subset (the decode error goes only to the log).
- about line 134: a URL that is not valid.
- about line 95: the actor is gone.
- about line 304: context.elicit throws.

Search the file for other declines or cancels that Multitool makes, and give each one a reason.

Each fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). No time limit, sleep, poll or retry. One full run. #elicitation-fixes