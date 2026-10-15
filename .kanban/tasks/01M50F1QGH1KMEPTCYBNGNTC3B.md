---
assignees:
- claude-code
position_column: done
position_ordinal: fffff580
title: 'Elicitation phase 2, task 23: install elicit only in an interactive session'
---
Plan: /Users/wballard/github/swissarmyhammer/elicitation-plan.md (sections 0, 2, 7, 9). Extras dbd91de adds `UserPresence` and `RunPlane.userPresence`. Router 99d00aa8 adds `SessionConfiguration.userPresence`.

Multitool installs the `elicit` global (and later the helpers) only when the session is interactive. A headless snippet sees no `elicit` global, and `help()` and the docs do not list it. Decide where Multitool reads the presence: from the run plane of the ToolContext at snippet start, or at mount.

Done when: a fixed-order test fails on the old code and passes with the change; one full run passes; the owner accepted the design before code. #elicitation-phase-2