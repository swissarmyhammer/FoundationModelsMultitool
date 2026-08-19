---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
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

- [ ] No test name, symbol, or prose in `Tests/FoundationModelsMultitoolTests/` calls running work "parked" or names a "run plane"
- [ ] Every Router symbol is still spelled as Router spells it
- [ ] Genuine-suspension prose is untouched

## Tests

- [ ] Ungated `swift test` green, both targets
