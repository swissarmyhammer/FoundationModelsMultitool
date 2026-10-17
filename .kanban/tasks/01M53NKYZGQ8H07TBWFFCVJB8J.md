---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: Record the connect generation of the attempt that got a context URL question
---
Found during ^aj384vm.

`openContextElicitation(_:request:context:)` in MCPServer+Elicitation.swift records `connectGeneration`, the current generation of the actor. It does not record the generation of the attempt whose client got the `elicitation/create`. A new connect and `disconnect()` move the generation before they retire the old client. An old client can deliver a request after the move (for example during `waitUntilTransportClosed` in `retireCurrentClient()`). That request then gets the new generation. The relay of its wire completion uses the old generation, thus `complete(elicitationId:generation:)` drops the completion. `endOldContextElicitations()` also skips the entry, because its generation is not older. The question can then stay open.

Work:
- Give the generation of the attempt to the elicitation handler (`registerElicitationHandler(on:)` gets it from `makeAttemptClient(over:transportID:generation:)`), and record that generation in `pendingContextElicitations`.
- Start with a fixed-order RED test (rule T1), then the fix. #elicitation-fixes