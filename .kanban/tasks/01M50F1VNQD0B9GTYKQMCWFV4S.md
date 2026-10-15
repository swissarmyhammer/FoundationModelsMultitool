---
assignees:
- claude-code
position_column: done
position_ordinal: fffff380
title: 'Elicitation phase 2, task 24: advertise MCP elicitation only for an interactive session'
---
Plan: /Users/wballard/github/swissarmyhammer/elicitation-plan.md (sections 0, 2, 7, 9).

MCPServer declares the elicitation capability (form and url) in its client capabilities at connect. It must declare it only for an interactive session, per session. Decide how a server pool learns the presence. Decide what ACPAgent's MCPComposition and the doctor probe (ToolsProber, which never advertises) must pass. Record each change that ACPAgent needs as a follow-up for the ACPAgent board.

Done when: a fixed-order test fails on the old code and passes with the change; one full run passes; the owner accepted the design before code. #elicitation-phase-2