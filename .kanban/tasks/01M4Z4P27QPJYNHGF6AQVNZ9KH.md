---
assignees:
- claude-code
position_column: done
position_ordinal: ffffef80
title: Use one ShellCommandGate for one wait only
---
#mail-step-5 #bad-test

The test "standard output and standard error each keep their own write order" (ShellRunnerTests.swift) used ONE gate (one FIFO) for three waits, one after the other. `GateReleaseRace.writeLine` writes the line, and it closes the write end only after the write (ShellCommandGate.swift `defer { close(descriptor) }`). In that interval the shell reads the line, closes its read end, prints the next line, and opens the SAME FIFO for the next wait. A FIFO open for reading ends at once while a writer holds the FIFO. Then the release closes its write end, and the `read` of the next wait gets end of file: status 1, no line. The script goes on and exits 0. The next release then sees the exit and gives `.commandExited` (the failure at ShellRunnerTests.swift:338), or, before 99e8db9, it blocked in the open for writing with no reader (the earlier hang).

The pid is correct: swift-subprocess calls `posix_spawn` directly, `/bin/sh` calls `execv` (same pid), and the builtin `read` with a redirect runs in the shell process. `hasExited` is false for a live shell (`p_flag` 0x4006).

Fix:
- `ShellCommandGate.release(whileAlive:)` throws `Failure` on a second release of one gate, and opens no FIFO.
- The write-order test uses one gate for each wait.
- Proof test in ShellCommandGateTests: a second release of one gate throws.