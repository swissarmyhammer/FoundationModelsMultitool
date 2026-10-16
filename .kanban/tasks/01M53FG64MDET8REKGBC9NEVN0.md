---
assignees:
- claude-code
depends_on:
- 01M53FG3MMBDB6DZ55TETQN9DN
position_column: todo
position_ordinal: '8380'
title: 'Group D (a): check the elicit url argument and give a clear error to the snippet'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (a).

Check `url` in elicit({ message, url }). These must give a clear argument error to the snippet, before any request:
- a relative text (today `URL(string:)` accepts "foo"),
- a scheme other than http or https (today "javascript:x" is accepted),
- a value that is not a string (today `url: 5` falls through to form mode).

Each fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). No time limit, sleep, poll or retry. One full run. #elicitation-fixes