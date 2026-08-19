---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0dmfbb3yh9dmvh2aw0zqpz0
  text: |-
    Sweep is complete. Procedure: grep the unit-test target for "park", "run plane", "run-plane", "RunPlane", "settled", and "plane". Read each hit in its context. Classify each hit as old vocabulary, Router symbol, or genuine suspension.

    Renames (8 files):
    - HostAndEmitterTests.swift: "run parks" -> "run backgrounds"; "The run parked" -> "The run backgrounded".
    - SuspendedContextTests.swift: "elevation parked it" -> "elevation backgrounded it"; "parked run" -> "background run" (3 sites); "run plane" -> "background run"; "session plane its runs park and post on" -> "session mailbox its runs background and post on"; "elevated runs park in" -> "elevated runs background into"; doc lines for `completionToken(of:)` and `settledTerminal(of:in:)`; two local variables `parked` -> `backgrounded`.
    - WaitToolTests.swift: "no run plane" -> "no background runs"; "a real run plane" -> "real background runs"; "whose run plane is read" -> "whose background runs are read".
    - HardeningTests.swift: "run-plane/notice globals" -> "background-run/notice globals".
    - SearchToolsToolTests.swift: "always parks" -> "always backgrounds"; "chance to park the call" -> "chance to background the call".
    - RunBindingTests.swift: test name "never parks" -> "never backgrounds".
    - ExamplesTests.swift: "lets a slow runCode park" -> "background".
    - RouterSessionMountTests.swift: "no run plane to park in" -> "no background runs to post into".

    Kept, by rule:
    - Router spelling `parkedRuns()` at 5 call sites (SandboxGlobalsTests, SuspendedContextTests x2, WaitToolTests, RunBindingTests, SandboxGlobalsFixtures).
    - Genuine suspension: HardeningTests "parked awaiting a pending tools.* promise" and "parked in the interpreter's promise pump"; JSCInterpreterTests "snippet parked on a pending call"; SuspendedContextTests local `parked` Task in the live-context-cap test — that call blocks on the latch and returns its own value, it never backgrounds.
    - All "settle" / "settled" / "settlement" prose and symbols: this is the current shipped vocabulary in Sources/ and in the fixtures.

    Note for the review step: the validator dump for this card was 671k characters. I read the validator list, not each rule body. The edits are prose and local-name renames only. No assertion changed.
  timestamp: 2026-08-19T18:27:57.411646+00:00
- actor: claude-code
  id: 01m0dmffxxjwy20dsq22m8x31q
  text: |-
    ### implement — changed
    - evidence: 8 files — Tests/FoundationModelsMultitoolTests/{HostAndEmitterTests,SuspendedContextTests,WaitToolTests,HardeningTests,SearchToolsToolTests,RunBindingTests,ExamplesTests,RouterSessionMountTests}.swift; root `swift test`: 361 tests in 30 suites, all passed, 0 failed, 0 skipped, 0 warnings
    - next: review
  timestamp: 2026-08-19T18:28:02.109486+00:00
- actor: claude-code
  id: 01m0dmqv2adw8m4mzcjn18gy8j
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit f281347) — 0 findings, 0 confirmed, 0 refuted; 8 files reviewed; 2 kanban files not reviewed (.reviewignore)
    - next: none. The task moved to done.
  timestamp: 2026-08-19T18:32:35.658859+00:00
- actor: claude-code
  id: 01m0dmr7rq0383egysk9awn03k
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files in Tests/FoundationModelsMultitoolTests/ renamed to the background-run vocabulary
    - test: green — root swift test 361/30, 0 skipped; IntegrationTests --build-tests clean
    - commit: f281347
    - review: clean — 0 findings; task moved to done
  timestamp: 2026-08-19T18:32:48.663233+00:00
position_column: done
position_ordinal: d680
title: Move the ungated unit-test target onto the background-run vocabulary
---
Task `^820xc9z` moved `Sources/` off "parked" and "run plane". Task `^v6hfhdv` moved `Tests/FoundationModelsMultitoolIntegrationTests/` onto the same words. `Tests/FoundationModelsMultitoolTests/` is the remainder, and it was out of scope for both by measurement rather than by oversight.

## What is still on the old vocabulary

Found while auditing `^v6hfhdv`. `Tests/FoundationModelsMultitoolTests/` carries "run plane" prose, for example in `SuspendedContextTests.swift`:

- "its answer is collected from the run plane rather than read off the call"
- "Carries the gated tool its snippets call, and the session plane its runs park and post on."

Read the whole target before you edit: the audit only sampled it.

## What must NOT change

The same four boundaries `^v6hfhdv` names, and for the same reasons:

- Router symbols keep Router's spelling: `ParkedRun`, `ToolContext.parkedRuns()`, `RoutedSessionActor.parkedRunDrainRoundLimit`, `settleParkedRuns`.
- Genuine suspension keeps the word "parked" — a thread parked on a condition variable, a waiter parked on a continuation, a nested `respond` parked on `generationGate.wait()`. Over-renaming is as much a defect as under-renaming.
- Do not touch `Sources/`, and do not touch the integration target.

## The vocabulary to move to

Read off the shipped surface, exactly as `^v6hfhdv` did: background runs that return a handle and complete later, with run state `running` | `complete` | `error` and a separate `result` field of `timeout` | `unknown` | `cancelled`. "run plane" -> "background runs"; "run-plane globals" -> "background-run globals"; a run that "parks" -> a run that "backgrounds".

## Acceptance Criteria

- [x] No test name, symbol, or prose in `Tests/FoundationModelsMultitoolTests/` calls running work "parked" or names a "run plane"
- [x] Every Router symbol is still spelled as Router spells it
- [x] Genuine-suspension prose is untouched

## Tests

- [x] Ungated `swift test` green, both targets (the integration suite moved to the nested `IntegrationTests/` package; root `swift test` now runs the unit target alone, and it is green)
