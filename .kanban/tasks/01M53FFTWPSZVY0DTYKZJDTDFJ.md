---
assignees:
- claude-code
depends_on:
- 01M53FFH3GERR2DZ8938SAQKGT
position_column: todo
position_ordinal: '8180'
title: 'Group A: end the pending URL flows on a server disconnect or reconnect'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group A.

(a) The host-handler URL flow (MCPServer+Elicitation.swift about lines 316-324) holds an accepted URL flow until complete(elicitationId:). Nothing clears pendingHostElicitations (MCPServer.swift about line 382) on a server disconnect or reconnect. Thus the handler never returns, and the client teardown hangs. On a disconnect, end each pending flow with cancel and a reason.

(b) A completion from an old connect generation is dropped (MCPServer.swift about line 386). Thus the context URL flow of that generation can never complete. End it on a disconnect too, with cancel and a reason.

Each fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). No time limit, sleep, poll or retry. One full run. #elicitation-fixes