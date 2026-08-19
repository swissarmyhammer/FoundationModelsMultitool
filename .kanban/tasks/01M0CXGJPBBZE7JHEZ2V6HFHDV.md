---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0czentt78rrf6s4p8ykm2c7
  text: |-
    Research done. What the survey of `Tests/FoundationModelsMultitoolIntegrationTests/` found:

    Files that carry the old vocabulary (7, exactly the set the card names): `Support/ScenarioRunner.swift`, `InBandCollectionCanaryTests.swift`, `RespondDrainTests.swift`, `ScenarioGradingTests.swift`, `ElevationTests.swift`, `Fixtures/ScenarioCallLog.swift`, `Fixtures/ScenarioTools.swift`.

    Files that keep "parked" and are NOT touched, because every use is genuine suspension: `Support/IntegrationGate.swift` (a thread parked on a condition variable, a waiter parked on a continuation, scenarios parked on the turnstile) and `NestedGenerationProbeTests.swift` (the nested `respond` parked on `generationGate.wait()`).

    Vocabulary chosen, read off the shipped surface in `Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift` so the harness and the product use one noun:

    - check name `runPlaneEmptyAtAnswer` -> `noBackgroundRunsAtAnswer` (constant `noBackgroundRunsAtAnswerCheckName`)
    - check name `runPlaneEmpty` -> `noBackgroundRunsAfterRespond`
    - evidence fields `parkedAtAnswer` / `parkedAfterRespond` -> `backgroundRunsAtAnswer` / `backgroundRunsAfterRespond`
    - local helper `ScenarioCallLog.parkedRuns()` -> `backgroundRuns()`; private `parkedRuns(atFirstTurnEndIn:reading:)` -> `backgroundRuns(atFirstTurnEndIn:reading:)`
    - printed field `parked=` on the RESPOND-DRAIN line -> `backgroundRuns=`
    - "run plane" -> "background runs"; "run-plane globals" -> "background-run globals"; a run that "parks" -> a run that "backgrounds"

    Router symbols keep Router's spelling and are only called: `ParkedRun`, `ToolContext.parkedRuns()`, `RoutedSessionActor.parkedRunDrainRoundLimit`, `settleParkedRuns`.

    Decision on the `PARKED-DRAIN [parkedRunDrain] ...` line in `InBandCollectionCanaryTests.swift`: LEAVE IT INTACT. It is a verbatim quotation of one gated run's output, from the era when the runner printed `PARKED-DRAIN` for a scenario named `parkedRunDrain`; it also carries a `terminals=` field the current runner no longer prints. Rewriting it would falsify a record of a run that happened. The choice is stated in a comment beside the block. Prose elsewhere that merely describes that run is reworded to say what was measured, rather than quoting a field name that no longer exists.
  timestamp: 2026-08-19T12:20:35.290619+00:00
- actor: claude-code
  id: 01m0d0dajj0dfjgab4bdrqvgpk
  text: |-
    Implementation landed. Seven files changed, all inside `Tests/FoundationModelsMultitoolIntegrationTests/`.

    What moved:

    - `noBackgroundRunsAtAnswerCheckName` = `"noBackgroundRunsAtAnswer"` replaces `runPlaneEmptyAtAnswerCheckName` = `"runPlaneEmptyAtAnswer"`.
    - `"runPlaneEmpty"` -> `"noBackgroundRunsAfterRespond"`, which now says which instant it grades instead of leaving a reader to infer it.
    - `InBandCollectionEvidence.parkedAtAnswer` / `.parkedAfterRespond` -> `.backgroundRunsAtAnswer` / `.backgroundRunsAfterRespond`, and the `IN-BAND-CANARY` line prints those field names.
    - `ScenarioCallLog.parkedRuns()` -> `backgroundRuns()`; the private `parkedRuns(atFirstTurnEndIn:reading:)` -> `backgroundRuns(atFirstTurnEndIn:reading:)`.
    - The `RESPOND-DRAIN` line prints `backgroundRuns=` where it printed `parked=`.
    - Test names: `respondSelfDrainsTheRunPlane` -> `respondSelfDrainsItsBackgroundRuns`, `theModelCollectsItsOwnParkedRun` -> `theModelCollectsItsOwnBackgroundRun`, `aRunLeftParkedAtTheAnswerFailsTheCanary` -> `aRunStillRunningAtTheAnswerFailsTheCanary`, with their `@Test` display names and the canary suite title.

    What stayed, and why each survivor is correct:

    - Router symbols, called and never renamed: `ParkedRun` (3 sites), `ToolContext.parkedRuns()` (2), `RoutedSessionActor.parkedRunDrainRoundLimit` (2), `settleParkedRuns` (1).
    - Genuine suspension, in `NestedGenerationProbeTests.swift`, `Support/IntegrationGate.swift` and the probe sections of `ScenarioRunner.swift` and `ScenarioTools.swift`: a thread parked on a condition variable, a waiter parked on a continuation, the nested `respond` parked on `generationGate.wait()`, a `respond` parked inside its own drain, a tool call parked for ever, scenarios parked on the turnstile.
    - The `PARKED-DRAIN [parkedRunDrain] …` transcript block, intact, with the choice stated in a comment beside it.

    One judgement call worth recording, because it is the one place "parked" described running work rather than suspension and could read either way: the `.toolStatus(.running)` comment in `streamTurn` said a slow call "went silent and parked". It describes a call that is still running and not reporting, so it is now "went silent while it ran".

    Discovered work, filed rather than done: `Tests/FoundationModelsMultitoolTests/` still carries "run plane" prose (for example in `SuspendedContextTests.swift`). Out of scope for this card by its own measured scope, so it is now `^vygr40z`.

    Verification: `swift build --build-tests` clean, `swift test` green at 361 tests / 30 suites and 59 tests / 11 suites — the expected counts, unchanged. The gated suite was not run; that is the orchestrator's step.
  timestamp: 2026-08-19T12:37:19.570644+00:00
- actor: claude-code
  id: 01m0d0dhk6b602h9bsvvh7rmvn
  text: |-
    ### implement — changed
    - evidence: 7 files — Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift, Tests/FoundationModelsMultitoolIntegrationTests/InBandCollectionCanaryTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/RespondDrainTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/ScenarioGradingTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/ElevationTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioCallLog.swift, Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift. `swift build --build-tests` clean; `swift test` green at 361 tests / 30 suites and 59 tests / 11 suites.
    - next: /review. The gated run the card's second Tests item asks for is the orchestrator's step, and it is the only acceptance item this step cannot close.
  timestamp: 2026-08-19T12:37:26.758743+00:00
- actor: claude-code
  id: 01m0d0fvnrsv7zq2nkkxkbz2aq
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — Build complete, 0 compiler warnings/errors (only a SwiftPM build-planning note about the third-party mlx-swift resource bundle, not this repo's code). `swift test` — FoundationModelsMultitoolTests: 361 tests / 30 suites passed; FoundationModelsMultitoolIntegrationTests: 59 tests / 11 suites passed (gated tests skip correctly, MULTITOOL_INTEGRATION unset).
    - next: gated suite run is a separate step, not run here.
  timestamp: 2026-08-19T12:38:42.616607+00:00
position_column: doing
position_ordinal: '8380'
title: Move the gated-scenario harness onto the background-run vocabulary
---
Task `^820xc9z` moved this package's shipped surface off "parked" and "run plane". Its measured scope was `Sources/`, and its acceptance criteria were all about model-facing strings and the doc comments beside them. The gated integration harness was left alone on purpose, and this card is what "on purpose" means — not a gap nobody noticed.

## What is still on the old vocabulary

`Tests/FoundationModelsMultitoolIntegrationTests/`:

- `Support/ScenarioRunner.swift` — the graded check names `runPlaneEmptyAtAnswerCheckName` (`"runPlaneEmptyAtAnswer"`) and `"runPlaneEmpty"`, the evidence fields `parkedAtAnswer` / `parkedAfterRespond`, and about 70 lines of narrative prose.
- `InBandCollectionCanaryTests.swift`, `RespondDrainTests.swift`, `ScenarioGradingTests.swift`, `ElevationTests.swift`, `Fixtures/ScenarioCallLog.swift`, `Fixtures/ScenarioTools.swift` — prose, test names, and the local helper `parkedRuns()`.

## What must NOT change

- Anything that spells a Router symbol: `ParkedRun`, `ToolContext.parkedRuns()`, `RoutedSessionActor.parkedRunDrainRoundLimit`. Those are a sibling repo's names and this package only calls them.
- The `PARKED-DRAIN [parkedRunDrain] elapsed=… parkedAtAnswer=[] parkedAfterRespond=[]` transcript line, unless the whole line moves together. It deliberately mirrors Router's own `parkedRunDrain` marker, so renaming half of it breaks the mirror it was built to be.
- Prose where "parked" means genuine suspension — every thread parked on a condition variable, a waiter parked on a continuation, a scenario parked on `generationGate.wait()`. That word is correct there.

## Why it is safe but not free

Nothing in the harness asserts on the wire values, so `^820xc9z` did not break it and this card is not urgent. But the check names appear in every gated transcript a reader grades a run from, so renaming them changes what those transcripts say. Do it in one pass, and take one gated run as the evidence.

## Acceptance Criteria

- [ ] No check name, evidence field, or test name in the integration target calls running work "parked" or names a "run plane"
- [ ] Every Router symbol is still spelled as Router spells it
- [ ] The `PARKED-DRAIN` mirror is either intact or moved whole, and the choice is stated in a comment
- [ ] Genuine-suspension prose is untouched

## Tests

- [ ] Ungated `swift test` green, both targets
- [ ] One gated run green, with the new check names read back out of the transcript
