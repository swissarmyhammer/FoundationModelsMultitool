---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: A second context URL question under a wire id in use has no entry, thus no wire completion and no connection end can end it
---
Found during ^179vr1r.

In MCPServer+Elicitation.swift, `openContextElicitation(_:request:context:)` does not add an entry when an open question of a context already uses the wire id. It writes `mcpElicitationWireIdInUse` and returns `false`. Then `resolve(_:urlElicitationId:linkedBy:)` calls `elicit(_:through:)` for the newer question with no entry in `pendingContextElicitations`.

Results:
- A wire completion of that id goes only to the earlier question.
- `endOldContextElicitations()` reads only the map, thus a disconnect or a new connect does not end the newer question.
- After the earlier question ends, its `defer` removes the entry, and the newer question still has no entry.

Thus the newer URL question can wait until the host session ends it. Decide the correct answer for the newer question (for example a cancel with a reason in `_meta`, at once, as the held flow of the handler does now with `replacedByNewerFlowReason`), and if the earlier question must end.

Start with a fixed-order test that fails on the current code: two URL questions of one bound context under one wire id; the test reads the result of each question on the wire. No time limit, sleep, poll or retry. #elicitation-fixes