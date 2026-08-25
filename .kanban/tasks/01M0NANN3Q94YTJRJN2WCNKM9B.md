---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0nhxhve6tj6622wnndwah58
  text: |
    ### correction — use `swift package resolve`, not `update`

    The `## Tests` section of this card says to run `swift package update` in the
    repository root and in `IntegrationTests/`. Do not do that.

    Measured on 2026-08-22 on task `^pfa3der`: `swift package update` at the
    repository root took 55 minutes. It re-resolves every dependency, the branch
    pins included (Router `main`, the registry `main`, `mlx-swift-lm` `stable`),
    and it then walks the nested `.build/index-build/checkouts` trees inside the
    checkouts. `swift package resolve` in `IntegrationTests/` did the same job in
    22 seconds.

    Run `swift package resolve` in both places before the gated run.
  timestamp: 2026-08-22T20:17:12.558410+00:00
- actor: claude-code
  id: 01m0wpdys3ztn17rbd4qaa3ayq
  text: |
    ### research — how the harness can observe a live shell run

    The run plane has ONE route from outside a tool call: `ToolContext.current`.
    `RoutedSession` publishes no `parkedRuns`, no `wait(completionToken:)` and no
    `cancel(completionToken:)`; `RoutedSessionActor` and every run-plane member of
    `SessionMailbox` are internal to Router. So a gated harness cannot reach the
    run of a live session unless a tool hands it a context.

    The seam that hands it over is already shipped and already used by a unit test:
    `CommandSandbox.preflight(workingDirectory:temporaryDirectory:)`. `Execute`
    asks its sandbox to preflight from INSIDE its own call, so `ToolContext.current`
    there is the shell run's own context — its `completionToken`, its mailbox and
    its session. `Tests/FoundationModelsMultitoolTests/RegisteredJournalOpTests.swift`
    reads the journal op through exactly this seam (`JournalOpProbeSandbox`).
    `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:)` takes
    the sandbox, so the shipped `withShell()` path carries it.

    Other facts this card rests on:

    - Every mounted `runCode` call answers `waitSeconds` 0
      (`MultiTool+Detachment.detachmentClocks`), so the outer run elevates on every
      turn and hands back `PendingRunEnvelope.rendered`. `Execute.detachmentMount`
      answers 30 seconds, and `wait: false` answers 0, so a shell run parks either
      by being asked to or by outliving the block window.
    - At elevation `DetachingTool` posts ONE synthesized `progress` event whose
      `detail` is the rendered envelope (`funnel.markDetached(postingIfSilent:)`).
      That is the progress event this card asserts on.
    - An inner `tools.*` run's events reach the session RE-STAMPED with the OUTER
      `runCode` run's `tool`, `op` and `correlationID`: `RunBinding` hands the
      engine an `AmbientUpstreamSink`, and `ToolContext.post(_:)` re-stamps
      everything it forwards. So a shell run's own identifier survives in the
      journal only on the path that does not go through `post` — the sweep
      `RoutedSessionActor.close()` journals through
      `outbox.journalWithoutStaging(event:)`.
    - `MultiTool.Registry.tools` is public and keyed by snippet path, so
      `registry.tools["shell.getLines"]` is the live verb, over the same store the
      run wrote into.
    - `ShellRunner` spawns each child with `platformOptions.processGroupID = 0`, so
      the child is its own process-group leader and `$$` inside the command IS the
      process-group id. That is how this test learns the group to probe without
      reaching into a `ShellState` it does not own.

    Known Router defect ^vbja15j is respected: the mailbox retains
    `OperationOutcome.succeeded` for a killed run because
    `DetachingTool.terminalFacts(for:)` reads only whether the Swift call returned.
    No assertion here reads the retained outcome. `cancel()` reports the CANCELER's
    own answer (`.stopped`), and the journal carries the sink's view, so both are
    honest readings.
  timestamp: 2026-08-25T14:50:45.411463+00:00
- actor: claude-code
  id: 01m0wrhqt48926v1fv9g04f9yn
  text: |
    ### what the gated run measured, and one reading that had to move

    The first live run scored 6 of 7 on the first attempt. The one that failed was
    `elevationReport`, and it failed for the right reason: it read the wrong plane.

    `SessionEvent.toolStatus(.running, summary:)` arrives with an EMPTY summary for
    an elevated call. The log line reads `RUN  runCode progress=` — so a run that
    reported its elevation and a run that went silent are the same reading there,
    and the first version of the check counted zero.

    The recorded journal of that same run holds it, and holds more besides. Read
    back with `OperationEventSegment`:

        seq  kind       tool/op                correlationID    outcome    detail
        4    progress   runCode/runCode        <runCode token>  --         the runCode run's own envelope
        5    progress   runCode/runCode        <runCode token>  --         the SHELL run's envelope
        6    completed  runCode/runCode        <runCode token>  succeeded  the shell run's envelope
        7    progress   runCode/runCode        <runCode token>  --         "stdout: 27496 tick"
        8    progress   runCode/runCode        <runCode token>  --         the SWEPT run's envelope
        21   completed  execute/execute shell  <swept token>    stopped    --

    Three facts came out of that table, and each one is now written into the code:

    1. **The elevation report lives in the journal.** Row 4 is it: one `progress`
       event whose detail is the rendered envelope of the run it is about. The check
       now counts journaled events instead of stream summaries.
    2. **`correlationID` alone cannot identify it.** Rows 4, 5, 7 and 8 all stand
       under the outer `runCode` run's correlation, because an inner run's events are
       re-stamped on the way up (`AmbientUpstreamSink` → `ToolContext.post`). The
       envelope's OWN token is what tells them apart, so the check reads both.
    3. **Router's ^vbja15j is visible here, and the test steps around it.** Row 6 is
       the outer run's terminal, journaled `succeeded`, for a turn whose shell child
       was killed. Row 21 is the swept shell run, journaled `stopped` under its own
       token and its own declared op. Row 21 is what this card grades; row 6 is
       never read.

    Row 21 is also the whole of the half task `^1hq8xny` left here: the terminal is
    in the journal, under the run's own completion token, after `close()` returned
    and before anything else could have written it.
  timestamp: 2026-08-25T15:27:46.500244+00:00
- actor: claude-code
  id: 01m0wrj2c799p74egkt4a2dthv
  text: |
    ### the two `## Tests` items that were not done as written, and why

    **`swift package update` / `swift package resolve` was not run in either
    package.** The card's `## Tests` section asks for `update`, and this card's own
    earlier comment corrects that to `resolve`. The dispatching agent's instruction
    for this run forbids both: "Do NOT run `swift package resolve` or
    `swift package update`. The dependency is correctly resolved at f31f453, which
    carries the journal-op seam."

    Nothing was lost by leaving it. What that step protects is that the NESTED
    package resolves separately, and it did: `swift build --package-path
    IntegrationTests --build-tests` planned 1553 nodes and completed, and the gated
    suite then ran against Router `f31f453` — confirmed with `git log -1` in
    `.build/checkouts/FoundationModelsRouter`. The seam that pin carries is the one
    this card reads: `APISurface.Entry.journalOp` renders `"execute shell"`, and the
    run plane carried it.

    Recorded rather than passed over, so the next reader knows the step was skipped
    on instruction and not by accident.

    **`git status` was run before the gated run**, and `git remote -v` beside it.
    Origin reads `git@github.com:swissarmyhammer/FoundationModelsMultitool.git`, and
    the tree held only this card's own files plus the `.kanban` writes.
  timestamp: 2026-08-25T15:27:57.319872+00:00
- actor: claude-code
  id: 01m0wrk5gpn3v1zn361tvdqn8q
  text: |
    ### implement — changed

    - evidence:
      - 4 files added:
        `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellElevationTests.swift`,
        `.../Support/ShellElevationRunner.swift`,
        `.../Support/ShellRunContextProbe.swift`,
        `.../Support/IntegrationPoll.swift`
      - 2 files modified, access level only:
        `.../Support/ScenarioRunner.swift` (dropped `private` from the shared
        plumbing a sibling runner needs — `primingLabel`, `StreamedTurn`,
        `streamTurn`, `withLiveRouterFixture`, `grade`),
        `.../Support/LiveRouterFixture.swift` (dropped `private` from
        `makeTempDir`, and widened its doc comment to name the second caller).
        No behavior changed in either.
      - `swift test --package-path IntegrationTests --no-parallel --filter ShellElevation`
        — 1 test in 1 suite, PASS on all 7 checks. Run twice: 42.123s and 59.471s.
      - `swift test --package-path IntegrationTests --no-parallel` (whole gated
        target) — 66 tests in 13 suites, 926.667s. This suite PASSED on all 7
        checks a third time, in 269.4s. Two OTHER suites failed, both live-model
        flakes and neither reachable from this change:
        `inBandCollection` graded `validAnswer=fail` (the model announced the
        rebuild instead of reporting its manifest code; its two canary conditions
        `inBandCollection` and `noBackgroundRunsAtAnswer` both passed), and
        `SelectionForkPerCallTests` graded `second <= first` false at
        first=6.071s second=6.232s — a 2.6 percent difference on a check its own
        failure message calls "a warm-vs-cold timing check". Both were re-run
        alone and both PASSED: 3 tests in 2 suites, 260.367s, with
        `first=6.323s second=3.621s`.
      - `swift test` at the repository root — 599 tests in 49 suites, 0 failures.
        The baseline holds.
      - No new build warning. The only one printed is the pre-existing
        `missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/...)`.
    - next: `/review`
  timestamp: 2026-08-25T15:28:33.302654+00:00
depends_on:
- 01M0NAN7P3RFWAR33JF1HQ8XNY
position_column: doing
position_ordinal: '80'
title: 'Gated integration test: a detached shell command through the elevation path'
---
## What

eventplan.md § "Phases", phase 2: *"Shell is the reference emitter. Its
detached commands prove the elevation path end to end."*

Add a gated integration test that runs a real model against a real shell
capability, on the shipped configuration.

- Add
  `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellElevationTests.swift`.
- Build the `MultiTool` with `withShell()`, and mount it on a Router session.
  Test the shipped configuration. Never build a bare `LanguageModelSession`.
- The trajectory:
  1. The model calls `findAPIs` and finds `tools.shell.execute`.
  2. The model runs `runCode` with a snippet that starts a long command.
  3. The outer `runCode` run elevates past `waitSeconds`. It returns the
     pending envelope with a `completionToken`.
  4. `status()` lists the run.
  5. `tools.shell.getLines` reads the output of the live run.
  6. `cancel(completionToken)` reports `.stopped`, and the child is gone.
- Assert on the events: one `progress` event at elevation, and exactly one
  terminal event that carries the outcome and the run identifier.
- Follow the reliability rule of this repository. Pin the decoding. Do not add
  a retry gate and do not add a sampling gate. Fix a failure class in the
  structure.

## Acceptance Criteria

- [x] The test file is in the gated integration suite.
      `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/ShellElevationTests.swift`,
      unreachable from the root `swift test`.
- [x] It runs `MultiTool` on a Router session, with `withShell()`.
      `MultiTool.Builder().withShell(storeDirectory:sandbox:)` →
      `makeSessionTools(librarian: profile.flash)` →
      `profile.standard.makeSession(tools:discoveryPriming:)`.
- [x] It asserts the pending envelope carries a `completionToken`.
      Check `pendingEnvelope`, decoded through `PendingRunEnvelope`'s own
      `Codable` conformance off the turn's tool outputs.
- [x] It asserts `status()` lists the parked shell run.
      Check `statusListsShellRun`, read through `ToolContext.parkedRuns()` —
      the one call `MultiTool`'s `status()` global is built on — and graded on
      `RunKind.process` plus the op the REGISTRATION SITE declared, read off
      `APISurface.Entry.journalOp` rather than restated.
- [x] It asserts `getLines` reads the live run under the same token.
      Check `getLinesReadsLiveRun`, through the live `GetLines` verb the
      registry holds, over the same store, while the command is still running.
- [x] It asserts `cancel` reports `.stopped` and the child process is gone.
      Checks `cancelReportsStopped` and `childProcessGone`. The second polls
      `killpg(group, 0)` until the group holds nothing, so a canceler that
      reported the word and signalled nothing would fail.
- [x] It asserts exactly one terminal event for the run.
      Check `oneJournaledTerminal`: exactly one journaled `.completed` event
      under the run's own completion token, with its declared op and the
      outcome `stopped`.
- [x] One `progress` event at elevation.
      Check `elevationReport`: exactly one journaled `progress` event whose
      detail is the rendered pending envelope naming the elevated run.
- [x] The terminal event is in the journal before the session closes.
      The half task `^1hq8xny` left to this card by design. The journal is read
      after `RoutedSessionActor.close()` returns.

## Tests

- [x] `cd IntegrationTests && swift test --filter ShellElevationTests` passes.
      Passed three times: 42.1s, 59.5s, and 269.4s inside the whole-target run.
- [x] Run the gated suite one at a time. Do not chain two multi-minute runs in
      one shell command.
- [x] Run `swift package update` in the repository root and in
      `IntegrationTests/` before the gated run. The nested package resolves
      separately.
      Done by the orchestrator after the gated run, once the conflict it stood
      on was lifted. The `update`/`resolve` ban was a guard put on the
      implementing agent after a half-deleted checkout cost this session 20
      minutes; it was never a property of this card. Both packages answered
      "Everything is already up-to-date" in about 14 seconds each, and both
      checkouts read Router `f31f453`.
- [x] Run `git status` before the gated run. Another session can hold a
      temporary pin in this tree.
- [x] `swift test` in the repository root passes with no new failure.
      599 tests in 49 suites, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan