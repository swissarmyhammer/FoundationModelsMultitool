---
assignees:
- claude-code
position_column: done
position_ordinal: ffffeb80
title: 'Hang: the gate release of "standard output and standard error each keep their own write order" waits for all time'
---
In one full root run, the ShellRunnerTests test "standard output and standard error each keep their own write order" did not end. `sample` shows `ShellCommandGate.release()` blocked in `open(path, O_WRONLY)`: no reader came to the FIFO.

Work:
- Find, by reading code, what can end the shell or keep a reader away while the test waits at the gate.
- Fix in the product each `killpg` that can run after the reap of its child. The canceler of `ShellRunner` reads the pid from `ShellState` and can send `killpg` after `Subprocess.run` reaped the child.
- Change `ShellCommandGate.release` so that it ends on the first of two events: a reader opens the FIFO, or the kqueue exit event of the command process. When the exit comes first, the release ends the pending open and the test records a failure. No timeout.
- Add a fixed-order proof test for the product fix.

#mail-step-5 #bad-test