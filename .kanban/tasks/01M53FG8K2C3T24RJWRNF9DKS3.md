---
assignees:
- claude-code
depends_on:
- 01M53FG64MDET8REKGBC9NEVN0
position_column: todo
position_ordinal: '8480'
title: 'Group D (b): throw an argument error for helper limits that no answer can satisfy'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (b).

The elicit.* helpers accept limits that no answer can satisfy. Throw an argument error ("elicit.<m>: " plus the usage text) before the request for:
- elicit.chooseMany with min above the option count,
- elicit.askNumber({min: 0.2, max: 0.8, integer: true}) (no integer in the range),
- elicit.choose and elicit.chooseMany with duplicate options.

Each fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). No time limit, sleep, poll or retry. One full run. #elicitation-fixes