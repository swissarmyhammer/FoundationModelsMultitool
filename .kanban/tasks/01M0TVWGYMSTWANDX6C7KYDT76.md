---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0ty7h3ny7dr1fbd21hwhn43
  text: |-
    Research, and the diagnosis confirmed against the code.

    `Execute.report(of:in:)` in `Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift` does:

        let stream = ShellOutputChunkStream()
        var running = runner
        running.outputChunkStream = stream

    `ShellRunner` is a struct, so `running` is a copy and the assignment REPLACES the one stream the runner carries. `ShellCapability` puts the host stream there (`ShellRunner(state:outputChunkStream:sandbox:)`), thus a host that subscribes reads nothing. The card is correct.

    Why the substitution is there, and what a fix must keep:

    1. The verb drains the stream to post one `progress` event for each chunk, and it calls `finish()` when the run ends so the drain task can end. A host stream outlives the run, and `finish()` on it would end the host's subscription for good.
    2. `ShellOutputChunkStream` states "One consumer. Two loops that read at the same time divide the events between them, and neither one sees all of them." So the verb must NOT read the host stream: it would take events away from the host.

    Shape 2 of the card (drain the configured stream) is therefore refused by the type's own contract, whatever end marker it used. Shape 1 (tee into both) is the one that holds both promises, and it is the one this card takes.

    The two tee points in `ShellRunner`:
    - `consume(_:commandID:)` — `outputChunkStream?.send(...)` for each raw chunk.
    - `run(_:)` — `defer { outputChunkStream?.complete(commandID:) }`, the one terminal marker.

    Both must reach the host stream and the per-run stream of the verb.

    Test ground: `ShellExecuteTests` is the suite that spawns commands; `ShellCapabilityTests` states "No test here spawns a command", so the new tests go in `ShellExecuteTests`. A test that builds a real `ShellCapability` must replace the runner's `registry` with a private `ProcessRegistry()`, because the capability takes `ProcessRegistry.global` and an ordinary test must not touch the process-wide instance.
  timestamp: 2026-08-24T22:28:34.549474+00:00
- actor: claude-code
  id: 01m0tyepeggmxzexfe3b584ybx
  text: |-
    Implementation landed, shape 1 of the card.

    `ShellRunner` now carries TWO live views and tees into both:
    - `outputChunkStream` — the host's, which `ShellCapability` sets and which
      outlives every run. Unchanged in name and meaning.
    - `callerOutputChunkStream` — new, private to ONE run, which the caller of that
      run drains and ends itself.
    - `outputChunkStreams` — a private computed list of the two that are there. The
      two tee points read that one list, thus neither can reach a view the other
      misses: `consume` sends each chunk into every view (the list is read one time,
      above the loop), and the `defer` of `run` completes every view.

    `Execute.report(of:in:)` now writes its per-run stream into
    `callerOutputChunkStream` instead of over `outputChunkStream`. Nothing else of
    the verb moved: the pump, the two `finish()` calls and the `progress` events are
    what they were.

    A run with no view at all answers an empty list, so both tee points do nothing,
    which is what the path with no host and no caller did before.

    TDD record. The chunk test failed first for the right reason — the host stream
    held ZERO events (`written == ""`, `events == []`), which is the card's defect
    exactly. The progress test passed from the start, which is its purpose: it is
    the guard that holds the `progress` events to what they are today, and it is
    what would have caught shape 2 splitting those events between the host and the
    verb.

    Interesting: `ShellCapabilityTests` states "No test here spawns a command", so
    the two new tests stand in `ShellExecuteTests`. Each one builds a real
    `ShellCapability`, takes its `Execute` verb, and copies the runner with a
    private `ProcessRegistry()` — the capability takes `ProcessRegistry.global` and
    an ordinary test must not touch the process-wide instance.
  timestamp: 2026-08-24T22:32:29.392861+00:00
- actor: claude-code
  id: 01m0tyex26ak8bhsrce2nrnfnm
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift, Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift, Tests/FoundationModelsMultitoolTests/ShellExecuteTests.swift. `swift test`: 588 tests in 47 suites passed, 0 failures, 0 warnings from the package.
    - next: /review
  timestamp: 2026-08-24T22:32:36.166439+00:00
- actor: claude-code
  id: 01m0tyrer91t82qbdmgxd8zjm8
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 58cf703) — 0 findings, 0 confirmed, 0 refuted, 7 validator attempts, 0 failed, 0 skipped. Reviewed Execute.swift, ShellRunner.swift, ShellExecuteTests.swift; 4 `.kanban/` files excluded by `.reviewignore`.
    - next: task moved to `done`. No findings section appended.
  timestamp: 2026-08-24T22:37:49.193293+00:00
- actor: claude-code
  id: 01m0tys89wh1e5t8n8ed246y2s
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (Capabilities/Shell/ShellRunner.swift, Capabilities/Shell/Execute.swift, Tests/ShellExecuteTests.swift). `ShellRunner` gained `callerOutputChunkStream` beside the host `outputChunkStream`, with a private computed `outputChunkStreams` that both tee points read. `Execute` changed one line. TDD held: the chunk test first failed with `events == []`, the defect word for word.
    - test: green — swift test run twice, 588 passed in 47 suites, 0 failed, 0 skipped. No stray process after either run.
    - commit: 58cf703 fix(shell): give host-supplied output stream its own tee point
    - review: clean — zero findings; the task is in done.

    **Why the substitution existed, and why the fix keeps both reasons.** The implementer verified each before acting: the verb calls `finish()` on its own view at the end of a run, and a host stream outlives every run, thus `finish()` must not reach it. And `ShellOutputChunkStream` documents one consumer — *"Two loops that read at the same time divide the events between them"* — thus the verb must not drain the host's stream, or it would steal the host's chunks. Draining the configured stream was refused for that reason, and the tee is the shape that holds both constraints.
  timestamp: 2026-08-24T22:38:15.356752+00:00
position_column: done
position_ordinal: f180
title: A host-supplied ShellOutputChunkStream never receives a chunk
---
## What

`ShellCapability(storeDirectory:sandbox:outputChunkStream:)` and
`MultiTool.Builder.withShell(...)` both take a `ShellOutputChunkStream`, and both
carry it to `ShellRunner.outputChunkStream`. A host that subscribes to that
stream reads nothing, because `Execute` replaces it for each run.

`Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`,
`report(of:in:)`:

    let stream = ShellOutputChunkStream()
    var running = runner
    running.outputChunkStream = stream
    let pump = Task { await Self.reportOutput(of: stream, to: context) }

The verb needs a stream of its own: it drains that stream to post one `progress`
event for each chunk, and it calls `finish()` on it when the run ends, so it
cannot share a stream that outlives the run. But the assignment DROPS the stream
the host configured, so `ShellRunner.consume` tees into the private stream and
into nothing else.

Two shapes answer it, and the choice is the work of this card:

1. `ShellRunner.consume` tees into BOTH — the private stream of the verb and the
   configured one. `ShellOutputChunkStream.send` never blocks, so a second tee
   costs the child nothing.
2. `Execute` drains the CONFIGURED stream where one is there, and makes a
   private one only where none is. `finish()` then ends a stream the host still
   holds, which is wrong for a host that watches more than one run, so this
   shape needs a per-run end rather than `finish()`.

Shape 1 is the one taken. Shape 2 is refused by the contract of
`ShellOutputChunkStream` itself: it hands each event to ONE consumer, so a verb
that drained the host's stream would take the host's chunks away from it,
whatever end marker it used.

## Acceptance Criteria

- [x] A `ShellOutputChunkStream` handed to `ShellCapability` receives the output
      chunks of a run, and its terminal marker.
- [x] The `progress` events `Execute` posts are unchanged.
- [x] A run with no configured stream behaves exactly as it does today.

## Tests

- [x] A test subscribes to a stream handed to `ShellCapability`, runs one
      command through `tools.shell.execute`, and reads the chunks that command
      wrote.
- [x] A test holds the `progress` events of that same run to what they are
      today.

Found while implementing ^zpdk266, which wired the parameter the card asked for.
#phase-2 #eventplan