---
assignees:
- claude-code
position_column: done
position_ordinal: ffffee80
title: End the wait for a gated command when the call that must start it ends
---
#mail-step-5 #bad-test

Gap: commit cebc030 added the test hook `ShellState.waitForCommand(holding:)` and the fixture `ShellCommandGate.release(commandIn:)`. Five sites in BackgroundSettleGraceTests use them. When the test step never calls execute, the command never starts, and the wait has no end.

Fix: the release also ends when the call that must start the command ends. Then the test records an issue with what the call returned. `waitForCommand(holding:)` ends with no token when its task is cancelled, thus no waiter stays behind. All waits end on events, not on time.

Proof: a fixed-order test where the call ends with no execute. The old behavior shows as a failed check, not as a hang.