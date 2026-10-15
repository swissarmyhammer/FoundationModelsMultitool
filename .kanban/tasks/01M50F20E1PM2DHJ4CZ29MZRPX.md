---
assignees:
- claude-code
position_column: done
position_ordinal: fffff480
title: 'Elicitation phase 2, task 25: a downstream MCP elicitation in a headless session gets cancel with a reason'
---
Plan: /Users/wballard/github/swissarmyhammer/elicitation-plan.md (sections 0, 2, 7, 9).

In a headless session, Extras dbd91de already answers each question through context.elicit at once with `.cancel(reason: RunPlane.noUserPresentReason)`, with no event and no stored question. Find what is left on the MCP route. For example, the reason must go in `_meta` of the MCP result, because ElicitResult has no reason field. Add the test.

Done when: a fixed-order test fails on the old code and passes with the change; one full run passes; the owner accepted the design before code. #elicitation-phase-2