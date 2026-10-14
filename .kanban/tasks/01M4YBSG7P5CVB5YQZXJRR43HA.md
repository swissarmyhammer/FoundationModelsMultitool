---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Remove the 5 s time bound behind a connect that has not ended
---
The MCP client queue lets a later operation pass a connect that has not ended after `clientConnectStragglerGracePeriod` (5 s). This is a time bound in product code. Replace it with an event, as the fix in 7808212 did for the disconnect turn. Do not start before the owner gives the order. #mail-step-5 #defect