---
assignees:
- claude-code
depends_on:
- 01M0NAMWPXE0GJ7SGW6ZPDK266
position_column: todo
position_ordinal: '8e80'
title: Kill shell process groups in the session-end sweep
---
## What

eventplan.md § "Elevation: waitSeconds and the completion token": *"Parked runs
die with the session."* The sweep processes each kind with that kind's own
semantics: *"Shell runs get `killpg(SIGKILL)` and post `.stopped`."*

Router's `SessionMailbox.sweep()` calls the canceler that each parked run
supplied. The shell canceler already sends `killpg(SIGKILL)` and returns
`.stopped`. This task proves the whole route, and it closes the holes.

- Make sure that a shell run parks with `RunKind.process` and with the
  `killpg` canceler.
- Make sure the terminal event of a swept run reaches the journal before the
  session closes. There must be no orphan and no hole in the durable record.
- Make sure the `atexit` backstop in `ProcessRegistry` does not fight the
  sweep. The sweep runs first, and the backstop finds nothing left.

## Acceptance Criteria

- [ ] A parked shell run carries `RunKind.process`.
- [ ] Session teardown kills the child process group of each parked shell run.
- [ ] The swept run posts a terminal event whose outcome is `.stopped`.
- [ ] The terminal event is in the journal before the session closes.
- [ ] No child process outlives its session.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift`.
- [ ] A test starts `sleep 60` detached, tears the session down, and asserts
      the process is gone.
- [ ] A test asserts the terminal event of the swept run carries
      `OperationOutcome.stopped`.
- [ ] A test with two parked shell runs asserts that each one gets its own
      terminal event.
- [ ] `swift test --filter ShellSessionSweep` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan