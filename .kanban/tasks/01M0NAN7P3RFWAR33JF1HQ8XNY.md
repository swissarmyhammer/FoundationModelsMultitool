---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0wk9hpr1exrasth3mmfc3rv
  text: |-
    Picked up. Research notes before writing tests.

    The route, end to end, as it stands in the tree today:

    - `Execute` conforms to `DetachmentParameterProviding` with `detachmentRunKind = .process` and `detachmentCanceler(forCompletionToken:)` returning `ShellRunner.canceler(completionToken:)`. `ToolDetachment.wrapping` -> `DetachingTool` reads both and gives them to `SessionMailbox.park(tool:op:kind:completionToken:settling:canceler:)`. So a parked shell run already carries `RunKind.process` and the `killpg` canceler.
    - `SessionMailbox.sweep()` walks `parkOrder`, awaits each run's canceler, and produces exactly one terminal event for each run: the natural one when the run settled during the canceler await, else a synthesized `.completed` event carrying the canceler's outcome.
    - `RoutedSessionActor.close()` calls `mailbox.sweep()` and then journals every returned event through `outbox.journalWithoutStaging(event:)` before it returns. That is the "terminal event is in the journal before the session closes" half, and it lives in Router, not here.
    - The shell canceler kills the group and marks the record `.killed`. `Execute.postTerminal` maps `.killed` to `OperationOutcome.stopped`, so both the natural terminal and the synthesized terminal read `.stopped`.
    - `ProcessRegistry` deregistration happens in the `defer` inside the spawn closure of `ShellRunner.run`, BEFORE swift-subprocess reaps the child. So there is no window in which a reaped and recycled pid is still registered, and the `atexit` backstop cannot signal a group it does not own.

    Two facts that shape the tests:

    1. `SessionMailbox.sweep()` is `internal` to `FoundationModelsRouter`. A plain `import` cannot reach it. Trying `@testable import FoundationModelsRouter` next; if SwiftPM's debug testability does not carry to the dependency, the test will drive the sweep's per-run contract through the one public seam (`ToolContext.parkedRuns()` plus `ToolContext.cancel(completionToken:)`), documented as standing in for the internal sweep.
    2. The direct child stays an unreaped zombie for a short window after `killpg`, so "the process is gone" cannot be asserted with a single read. The test polls `killpg(pgid, 0)` until it reports `ESRCH`. That check is scoped to a process group the test itself spawned, and signal 0 sends nothing.
  timestamp: 2026-08-25T13:55:55.224829+00:00
- actor: claude-code
  id: 01m0wm4jcf3r9dj4natsnbrsan
  text: |-
    Implementation notes, and the two things the next agent needs.

    **The sweep is reachable, and the tests drive the real one.** `SessionMailbox.sweep()` is `internal` to Router, but SwiftPM builds every dependency with testability in the debug configuration, so `@testable import FoundationModelsRouter` reaches it from this test target. A probe test proved that before the suite was written. So `ShellSessionSweepTests` calls `mailbox.sweep()` itself; it does not stand in a hand-rolled copy of the sweep. The file states why it takes that import.

    **The RED step was two mutations of `Execute.detachmentCanceler`, both reverted.** The production code already carried the behaviour, so the tests could not fail by being written first. They were made to fail on purpose instead:

    1. `detachmentCanceler` returns `nil`, so the engine's cooperative canceler parks instead. `theTerminalEventOfASweptShellRunCarriesStopped` failed on `terminal.outcome == .stopped` and on `record.status == .killed`; `eachOfTwoParkedShellRunsGetsItsOwnTerminalEvent` failed on the `.stopped` check. The two process-group tests still PASSED, because cancelling `workTask` cancels `Subprocess.run`, whose own `defer` still kills the group. So mutation 1 alone does not prove those two bite.
    2. `detachmentCanceler` returns `{ .stopped }` — a canceler that reports the right word and signals nothing. `sessionTeardownKillsTheProcessGroupOfEachParkedShellRun` failed on both groups, `theSweepDrainsTheProcessRegistry` failed on the drain, and the store record failed. That is the mutation that proves the reading is the process group and never the returned word.

    `git checkout` restored `Execute.swift`; `git status` shows `Sources/` clean.

    **Reaping is why the group check is a poll and not one read.** `killpg` kills the tree at once, but the leader stays an unreaped child of the test process until swift-subprocess reaps it, and a group holding a zombie still answers `killpg(pgid, 0)`. So the test polls until the group answers `ESRCH`, which is also the proof that the child was reaped and left no orphan. Every signal the file sends is signal 0 — it sends nothing — and every group it names is one the file spawned.

    **Duplication removed rather than added.** The new suite needs the two steps `ShellExecuteTests` already had privately: mount an `Execute` on `ToolDetachment.wrapping` with `RunBinding.innerCallMount`, and poll the run plane until the run parks. Copying them would have been a `duplication` blocker, so both moved to `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift` as `ShellRunPlane.mounted(_:inheriting:)` and `ShellRunPlane.parkedRuns(in:count:)` / `parkedRun(in:)`. `ShellExecuteTests` now calls them and lost its `pollInterval`, `parkArrivalDeadline` and `ParkedRunAbsent`. Six call sites moved, and the suite still passes.

    **One hole found that this repository cannot close: ^tsdzzzs.** `DetachingTool.settle` builds the run's terminal event from `terminalFacts(for: result)`, and `SessionMailbox.park(settling:)` retains THAT event. A `.process` run is stopped by a canceler that kills the group and never cancels `workTask`, so `Execute.call` returns normally and the retained event reports `OperationOutcome.succeeded` for a run a `SIGKILL` ended. The sink still sees `.stopped`, because `Execute` posts its own terminal through `RunEventFunnel` first and the funnel drops the engine's. So only the mailbox's retained value is wrong, and `wait(completionToken:)` on a stopped run reads it. The sweep uses that natural terminal only when a run settles inside the window of its own canceler await — two actor hops against a reap, a drain and a file read — so it practically always synthesizes with the canceler's `.stopped` instead. Narrow, but real. Recorded as ^tsdzzzs, which needs a Router change.

    **Nothing in `Sources/` changed.** The card is a proof card: the route was already correct, and what was missing was the evidence.
  timestamp: 2026-08-25T14:10:40.655825+00:00
- actor: claude-code
  id: 01m0wm4rwd54szvq4rexh6bz8p
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift (new, 4 tests), Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift (new), Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift (uses the shared fixture). `swift test --filter ShellSessionSweep`: 4 tests in 1 suite passed. `swift test`: 599 tests in 49 suites passed, 0 failures (baseline 595 in 48). The one build warning is the pre-existing out-of-scope `missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`. `Sources/` is unchanged.
    - next: /review
  timestamp: 2026-08-25T14:10:47.309789+00:00
depends_on:
- 01M0NAMWPXE0GJ7SGW6ZPDK266
position_column: doing
position_ordinal: '80'
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

- [x] A parked shell run carries `RunKind.process`.
- [x] Session teardown kills the child process group of each parked shell run.
- [x] The swept run posts a terminal event whose outcome is `.stopped`.
- [x] The terminal event is in the journal before the session closes.
      Proved by composition, and the composition is stated here because the
      two halves have different owners. `RoutedSessionActor.close()` journals
      exactly what `SessionMailbox.sweep()` answers with, through
      `outbox.journalWithoutStaging(event:)`, before it returns; that half
      lives in Router and needs a loaded model to drive, so it belongs to the
      gated integration card ^wcnkm9b. This card proves the half that Router
      journals: the sweep answers ONE terminal event for each run that was
      parked, each under that run's own completion token, and it leaves the
      run plane empty — no hole, and no orphan.
- [x] No child process outlives its session.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift`.
- [x] A test starts `sleep 60` detached, tears the session down, and asserts
      the process is gone. It starts a `sleep 60 & sleep 60` TREE, so the
      reading proves the whole process group died and not the leader alone.
- [x] A test asserts the terminal event of the swept run carries
      `OperationOutcome.stopped`.
- [x] A test with two parked shell runs asserts that each one gets its own
      terminal event.
- [x] A test asserts the sweep drains the process-group registry, thus the
      `atexit` backstop finds nothing left to kill.
- [x] `swift test --filter ShellSessionSweep` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan