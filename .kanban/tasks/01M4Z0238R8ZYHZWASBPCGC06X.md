---
assignees:
- claude-code
position_column: done
position_ordinal: ffffed80
title: End each gate release on the exit of the command
---
Five tests in BackgroundSettleGraceTests released a ShellCommandGate with the old release(). That release opens the FIFO for writing and waits for a reader with no end. When the command ended before it came to the gate, the test did not fail; it waited for all time. Change each site to the event form: get the completion token from ShellState.waitForCommand(holding: gate path), the process from ShellState.groupToCancel(commandID:), then release(whileAlive: pid). Record the record of the command as a failure on .commandExited. Remove the old release() when it has no user. #mail-step-5 #bad-test