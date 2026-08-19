---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
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
