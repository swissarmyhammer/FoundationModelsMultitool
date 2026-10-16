---
assignees:
- claude-code
depends_on:
- 01M53FGDHZJ8BFKNZGKK4K5V9R
position_column: todo
position_ordinal: '8780'
title: 'Test rule T1: each wait in a test also ends on the failure event, and fixtures close when the body throws'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), new test rule T1.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits. Fixtures close also when the test body throws.

Known cases:
- MCPElicitationTests about lines 767-771: if the second call never returns, held.release() never runs.
- elicitationRequest(on:) about line 346.
- `defer { Task { await server.disconnect() } }` (about lines 782, 799, 817, 839) is not awaited.

Search the whole test target for the same cause. One Task.sleep is left in the test target; remove it.

No .timeLimit, sleep, poll or retry. Do not delete a test. One full run. #elicitation-fixes