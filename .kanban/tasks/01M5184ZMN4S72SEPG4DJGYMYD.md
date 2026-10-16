---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Attribute a server elicitation to the right call when a server has concurrent calls (elicitation-plan task 26)
---
When one MCP server has two calls in flight, Multitool links a server `elicitation/create` only to the sole call in flight. With two calls, the question gets `cancel`.

Do:
- Start from the new design: one MCP client for each connect attempt.
- Find a way to link the question to the right call. Candidates: the related-request id or `_meta` of the MCP request, if the server sends it; or the progress token.
- If MCP gives no way to know the call, say so, and propose what to do (for example, ask through the session with no tool context).
- Send a short design to the owner before code.
- A fixed-order test with two calls in flight. It fails on the old code as a check.
- One full run. Push when green.

#elicitation-phase-3