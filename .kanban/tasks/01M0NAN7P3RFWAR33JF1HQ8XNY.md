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
- actor: claude-code
  id: 01m0wmk8154m92hw96ngm8k4fb
  text: |
    ### review — findings
    - evidence: 4 findings (4 confirmed, 0 refuted) from `review sha HEAD~1..HEAD` — Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift:22, Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift:25, Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift:92, Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift:230
    - next: card stays in `review`. Correct each finding, then run the review again.
  timestamp: 2026-08-25T14:18:41.573904+00:00
- actor: claude-code
  id: 01m0wmm4fh6k5gw5e91hpk5tpk
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 test files. This is a proof card: nothing in `Sources/` changed, because the route was already correct and what was missing was the evidence.
      - `Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift` (new, 4 tests) drives the REAL `SessionMailbox.sweep()`, reached through `@testable import FoundationModelsRouter`. It proves the child process group is gone by polling `killpg(pgid, 0)` to `ESRCH`, and not by trusting a returned word.
      - `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift` (new) and `ShellExecuteTests.swift`, which now calls the shared fixture.
      - The tests were mutation-proved. With `Execute.detachmentCanceler` returning `{ .stopped }` — the correct word, but no signal — the process-group test, the registry-drain test and the store record all failed. Both mutations were reverted.
    - test: green — `swift test --filter ShellSessionSweep` 4 of 4 passed; full `swift test` 599 tests in 49 suites passed, 0 failures. Baseline was 595 in 48.
    - commit: 89da88c — test(shell): prove the session-end sweep kills each child process group (^1hq8xny)
    - review: findings — 4 confirmed, 0 refuted, at `Fixtures/ShellRunPlaneFixtures.swift:22`, `Fixtures/ShellRunPlaneFixtures.swift:25`, `ShellSessionSweepTests.swift:92`, `ShellSessionSweepTests.swift:230`. Two are magic numbers; two ask to share one `pollInterval` constant and one `waitUntil()` poll helper across the test target rather than redefine them.

    Also filed during this iteration: a genuine Router defect, on the FoundationModelsRouter board as ^vbja15j. `DetachingTool.settle` builds the retained terminal from `terminalFacts(for: result)`, so a `.process` run stopped by `killpg` — which never cancels `workTask` — retains `OperationOutcome.succeeded`. Sinks still see `.stopped`, so only the value the mailbox retains is wrong. It cannot be fixed from this package.
  timestamp: 2026-08-25T14:19:10.705781+00:00
- actor: claude-code
  id: 01m0wn7cbbb1xbqbsce8pzedny
  text: |-
    Worked the four review findings. What each cause was, and where it was removed from.

    **The magic-number cause is a literal that stands as a CALL ARGUMENT, and not every literal.** `magic-numbers-swift` is swiftlint's `no_magic_numbers`, and the rule body states that it reports nothing for "a variable declaration, a stored property, a `static let`, an enumeration raw value, or a default parameter — each of those declarations names its value". So `private static let parkedRunSleepSeconds = 60` never reported, while `static let pollInterval = Duration.milliseconds(25)` did: the `25` is an argument of a call, and the declaration names the Duration rather than the number.

    Measured, and not guessed. swiftlint 0.65.0 over the HEAD copies of the two files, with `only_rules: [no_magic_numbers]`, reports exactly the two flagged lines and nothing else. The same run over the six files as they stand now reports 0 violations in 6 files. The pattern that answers it is the one this repository already used in `SuspendedContextTests`: name the number, then build the `Duration` from the name.

    **One poll now stands for the whole test target: `Fixtures/PollFixtures.swift`, holding `TestPoll`.** It owns the interval (25 ms), the deadline (10 s), a `holds(before:_:)` that answers whether a reading became true, and a `waitUntil(_:before:_:)` that records the `Issue` and throws when it did not. `waitUntil` calls `holds`, thus there is one loop.

    Removed, each one a duplicate the findings named:
    - `ShellRunPlane.pollInterval` and `ShellRunPlane.parkArrivalDeadline` — gone; `parkedRuns(in:count:)` now polls through `TestPoll.holds`.
    - `ShellSessionSweepTests.pollInterval`, `.processGroupArrivalDeadline`, `.processGroupExitDeadline`, `.registryDrainDeadline` and its private `waitUntil(before:_:)` — all gone.
    - `SuspendedContextTests.waitUntil(_:)`, `.readinessPollIntervalNanoseconds` and `.readinessDeadlineSeconds` — gone; its three call sites take `TestPoll.waitUntil` and now name what each one waits for. Nothing else of that pre-existing suite was touched, per the carve-out.
    - `ShellRunnerTests.pollInterval` and `ShellHistoryOpsTests.pollInterval` — both were the same `Duration.milliseconds(25)` under the same name. Neither was flagged, because neither file is in the diff, but "one shared `pollInterval` for the test target" is not reached while they stand. Their three sleep sites take `TestPoll.interval`; no other line of either file changed.

    **The four tests still bite exactly as before.** The reading of the process group is still a poll of `killpg(pgid, 0)` to `ESRCH`, under the same 10-second bound, and still `#expect(gone, ...)` for each group rather than a throw — the poll is what proves the child was reaped and left no orphan, and `#expect` reports both groups instead of stopping at the first. The prose that explains why the poll is real work moved from the deleted constant onto the doc comment of the test it belongs to.

    **One design note for the next agent.** `TestPoll.holds` takes `() async -> Bool`, thus a synchronous reading (`registry.registeredPids.isEmpty`) and a suspending one (`await state.runningProcess(commandID:)`) share it — Swift converts a non-async closure to an async parameter. That is what let `processGroup(of:in:)` and `ShellRunPlane.parkedRuns` drop their hand-rolled loops and still answer a value: each captures the read into a local `var` inside the closure.
  timestamp: 2026-08-25T14:29:41.355440+00:00
- actor: claude-code
  id: 01m0wn7kv2yjrvhq5ffawe39h9
  text: |
    ### implement — changed
    - evidence: 6 files — Tests/FoundationModelsMultitoolTests/Fixtures/PollFixtures.swift (new, holds `TestPoll`), Fixtures/ShellRunPlaneFixtures.swift, ShellSessionSweepTests.swift, SuspendedContextTests.swift, ShellRunnerTests.swift, ShellHistoryOpsTests.swift. All 4 review findings are now checked. `swift test --filter ShellSessionSweep`: 4 tests in 1 suite passed, 0 failures. `swift test`: 599 tests in 49 suites passed, 0 failures — the baseline held. `swift build --build-tests` carries exactly 1 warning, the pre-existing out-of-scope `missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`. swiftlint `no_magic_numbers` over the 6 files: 0 violations; over the HEAD copies of the two flagged files: the 2 flagged lines. `Sources/` is unchanged.
    - next: /review
  timestamp: 2026-08-25T14:29:49.026408+00:00
- actor: claude-code
  id: 01m0wngjza6a3eyhgcq0atfxgp
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (800adc0) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed; 6 files reviewed, 2 skipped by `.reviewignore`. All 4 findings of the pass on 2026-08-25 09:14 are corrected: the two `code-hygiene/magic-numbers-swift` literals moved into `TestPoll.intervalMilliseconds` and `TestPoll.deadlineSeconds` (swiftlint 0.65.0, `only_rules: [no_magic_numbers]`, reports 0 violations over the six files); the two `reuse/reuse` duplicates are gone, because `Tests/FoundationModelsMultitoolTests/Fixtures/PollFixtures.swift` now holds the one `TestPoll` of the target and `waitUntil(_:before:_:)` calls `holds(before:_:)`, thus one loop. No local `pollInterval` and no local `waitUntil` is left in `ShellSessionSweepTests`, `SuspendedContextTests`, `ShellRunnerTests` or `ShellHistoryOpsTests`.
    - next: card moved to `done`.
  timestamp: 2026-08-25T14:34:43.050818+00:00
- actor: claude-code
  id: 01m0wnh9c7wq778jj9j9mzw638
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 6 test files. All four findings of iteration 1 corrected, each cause removed from the whole file and not only the named line.
      - The two `magic-numbers-swift` findings: the cause is a numeric literal standing as a CALL ARGUMENT. swiftlint's `no_magic_numbers` exempts a literal that a declaration names directly, which is why `parkedRunSleepSeconds = 60` never reported while `Duration.milliseconds(25)` did. Each number is now named first, then used to build its `Duration`.
      - The two `reuse/reuse` findings: there is now one poll for the whole test target in the new `Tests/FoundationModelsMultitoolTests/Fixtures/PollFixtures.swift`. `TestPoll` holds the interval, the deadline, `holds(before:_:)` and `waitUntil(_:before:_:)`, and `waitUntil` calls `holds`, so there is one loop and not two. Every duplicate constant and duplicate `waitUntil` is gone from `ShellRunPlaneFixtures`, `ShellSessionSweepTests`, `SuspendedContextTests`, `ShellRunnerTests` and `ShellHistoryOpsTests`.
      - The sweep proof was not weakened. The process-group reading is still a poll of `killpg(pgid, 0)` to `ESRCH` under the same 10-second bound, and still `#expect(gone, …)` for each group rather than a throw, so both groups are reported and the reap-and-no-orphan proof holds.
    - test: green — `swift test --filter ShellSessionSweep` 4 of 4 passed; full `swift test` 599 tests in 49 suites passed, 0 failures. Baseline held. swiftlint `no_magic_numbers` reports 0 violations over the six files.
    - commit: 800adc0 — test(shell): share one poll helper and name each duration (^1hq8xny)
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings over 6 files, 7 validator passes attempted. The reviewer confirmed each prior finding is fixed in the code and not only marked, and ran swiftlint itself to check. Card landed in done.
  timestamp: 2026-08-25T14:35:05.991898+00:00
depends_on:
- 01M0NAMWPXE0GJ7SGW6ZPDK266
position_column: done
position_ordinal: f480
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

## Review Findings (2026-08-25 09:14)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift:22` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift:25` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift:92` `reuse/reuse` — Redefines `pollInterval` that already exists as `ShellRunPlane.pollInterval` with identical value (Duration.milliseconds(25)). This constant should be reused from the shared fixture rather than redefined. Remove the local `pollInterval` definition at line 92. Replace usages at lines 200 and 236 with `ShellRunPlane.pollInterval`.
- [x] `Tests/FoundationModelsMultitoolTests/ShellSessionSweepTests.swift:230` `reuse/reuse` — Reimplements `waitUntil()` utility that already exists in SuspendedContextTests at 0.91 semantic similarity. This is a generic polling pattern that should be shared rather than duplicated across test suites. Consolidate `waitUntil()` into a shared test utilities file (similar to how ShellRunPlaneFixtures.swift was created), or refactor to reuse the existing implementation from SuspendedContextTests.
