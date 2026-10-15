---
assignees:
- claude-code
position_column: done
position_ordinal: ffffec80
title: ShellState.groupToCancel waits with no end when the command already ended
---
The doc of ShellState.groupToCancel(commandID:) (before: pidToCancel) says that it gives nil when the command already ended. The code instead waits with no end in that case. A cancel of a command that ended can then hang. Make it end on an event: give nil when the record of the command is final. Add a fixed-order test that fails on the old code. Found during the fix of task 01M4YX8ZHVS1CJHJPS1G5RQKC8. #mail-step-5 #defect