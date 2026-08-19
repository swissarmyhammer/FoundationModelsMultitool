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
- actor: claude-code
  id: 01m0d0hf404za1x5wbcnnhy4d1
  text: |-
    ### commit — changed
    - evidence: f0cdc3e test(integration): rename gated harness to background-run vocabulary
    - next: gated run (orchestrator's step), then /review
  timestamp: 2026-08-19T12:39:35.296030+00:00
- actor: claude-code
  id: 01m0d0tmvadeyjrw085y01pp0e
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (f0cdc3e) — 0 findings, 0 confirmed, 0 refuted, 7 files attempted, 0 failed. The 4 skipped files are `.kanban/`, excluded by `.reviewignore`.
    - boundaries checked against the card's "What must NOT change", each one verified and each one held:
      - Router symbols keep Router's spelling and are only called: `ParkedRun`, `ToolContext.parkedRuns()`, `RoutedSessionActor.parkedRunDrainRoundLimit`, `settleParkedRuns`. No `typealias` in the target, so no symbol is aliased to hide the word. `ScenarioCallLog.backgroundRuns()` returns `[ParkedRun]` and its doc comment names `ToolContext.parkedRuns()` as Router's own spelling, so the wrapper points at the Router name instead of covering it.
      - Genuine suspension keeps "parked". `Support/IntegrationGate.swift` and `NestedGenerationProbeTests.swift` are untouched by this commit. Every removed "park" in the diff is the backgrounded-run sense.
      - The `PARKED-DRAIN [parkedRunDrain] …` block is intact, not half-renamed, and the comment beside it states the choice: it quotes one gated run verbatim, it carries a `terminals=` field the runner no longer prints, rewriting it would report words no run ever said, and the reader is told the runner prints `IN-BAND-CANARY … backgroundRunsAtAnswer= backgroundRunsAfterRespond=` today.
      - The old names are gone from the integration target. The only `runPlaneEmpty` / `parkedAtAnswer` / `parkedAfterRespond` text left in the target is inside that verbatim block. No assertion, failure message, or doc comment names an old check name.
      - `Sources/` is untouched by f0cdc3e. That was `^820xc9z`.
      - Prose moved with the identifiers: "run plane" -> "background runs", "run-plane globals" -> "background-run globals", a run that parks -> a run that backgrounds.
    - the two deliberate decisions, both confirmed on their merits:
      - `"runPlaneEmpty"` -> `"noBackgroundRunsAfterRespond"` rather than a bare `"noBackgroundRuns"`. Correct. It pairs with `noBackgroundRunsAtAnswer`, and the two names now say which instant each grades. A bare name would grade one of two instants and say neither.
      - The `.toolStatus(.running)` comment in `streamTurn`, "went silent and parked" -> "went silent while it ran". Correct. The event is `.running`, so the call is running and not suspended, and the sentence keeps the contrast it was written for: a slow call that streams progress against one that reports nothing while it runs.
    - next: the gated run. This card is left in `review` and not advanced, for one reason only, and it is not a finding: the second Tests item — one gated run green, with the new check names read back out of the transcript — is still open, and every prior step record names it as the orchestrator's step. Run the gated suite, check that item, then re-review to close.
  timestamp: 2026-08-19T12:44:36.074942+00:00
- actor: claude-code
  id: 01m0d0vpcjwfpqfyv9rk58mnsy
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files in the integration target; `runPlaneEmptyAtAnswer` -> `noBackgroundRunsAtAnswer`, `runPlaneEmpty` -> `noBackgroundRunsAfterRespond`, evidence fields and `ScenarioCallLog.parkedRuns()` -> `backgroundRuns()`
    - test: green — `swift test`, 361/30 and 59/11, zero failures, zero warnings
    - commit: f0cdc3e
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings across 7 files; every "must NOT change" boundary checked by hand and held
    - **held in review, correctly.** The card's second Tests item wants a gated run with the new check names read back out of the transcript, and that evidence does not exist yet. Running it now as the orchestrator's step; re-review to close after.

    The implement pass also flagged one place worth recording: the `.toolStatus(.running)` comment in `streamTurn` was the single spot where "parked" described work that was *running rather than suspended* — a call that streamed no progress. It now reads "went silent while it ran", which is the distinction this whole card exists to make.
  timestamp: 2026-08-19T12:45:10.418272+00:00
- actor: claude-code
  id: 01m0d1pz756m9anc1c4hspfgs8
  text: |-
    ### finish iteration 2 — green
    - gated: **green** — `MULTITOOL_INTEGRATION=1 swift test --no-parallel` at `f0cdc3e`, **59 tests / 11 suites / 844.6s**, every scenario PASS

    The card's second Tests item asked for the new check names read back out of the transcript. They are:

        SCENARIO [inBandCollection] result=PASS validAnswer=pass grounded=pass inBandCollection=pass
                                    noBackgroundRunsAtAnswer=pass noBackgroundRunsAfterRespond=pass

        IN-BAND-CANARY [inBandCollection] elapsed=190.3s backgroundRunsAtAnswer=[] backgroundRunsAfterRespond=[]
                                          waitCalls=3 returned=["rebuildArchive"] groundedIn=["rebuildArchive"]
                                          reply="Done. Your archive index rebuild is complete, and its manifest code is **58204**."

        RESPOND-DRAIN respondSelfDrain elapsed=85.5s backgroundRuns=0 waitCalls=1

        ✔ Suite "Gated in-band collection canary (the model collects its own background run)"

    So the graded check names, the evidence fields, the `RESPOND-DRAIN` counter and the suite title all read in the new vocabulary in a real run, which is the only place they were ever going to be read from. Nothing still prints "parked" or "run plane" for work that is running.

    `waitCalls=3` again — the same count the ungated `ScenarioGradingTests` pins as the recorded value, so the rename moved no behaviour.

    Whole run 844.6s against 689.4s for the previous green run. That is run-to-run spread on a shared machine, not a regression: the in-band canary alone took 190.3s here against 114.7s before, and nothing in this commit touches execution — only names.
  timestamp: 2026-08-19T13:00:04.197607+00:00
- actor: claude-code
  id: 01m0d1z989hbkmfjczycg8nfrk
  text: |
    ### review — findings
    - evidence: 1 finding, 1 confirmed, 0 refuted — `review sha f0cdc3e~1..f0cdc3e`, 7 files attempted, 0 failed, 4 `.kanban/` files excluded by `.reviewignore`. Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift:1396
    - gated evidence: accepted. The card's second Tests item is now closed by the "finish iteration 2 — green" record: `MULTITOOL_INTEGRATION=1 swift test --no-parallel` at f0cdc3e, 59 tests / 11 suites / 844.6s, every scenario PASS, and the new names read back out of the transcript — `noBackgroundRunsAtAnswer=pass noBackgroundRunsAfterRespond=pass`, `backgroundRunsAtAnswer=[] backgroundRunsAfterRespond=[]`, `RESPOND-DRAIN respondSelfDrain … backgroundRuns=0`. All 6 acceptance and Tests boxes are ticked.
    - why this pass is not clean: the same range now returns one confirmed finding that the previous pass did not raise. `"noBackgroundRunsAfterRespond"` is written as a string literal at the grading site, while the three check names beside it in the same function come from named constants. The rename introduced this line, so it is inside the reviewed diff.
    - scope of the fix: the finding names one line. Remove the cause from the whole file — every check name the runner grades must come from a named constant, so audit each grading site in ScenarioRunner.swift, not line 1396 alone.
    - next: /implement to close the finding, then re-review. The card stays in `review`. No gated re-run is needed for a constant extraction that changes no wire value, but the ungated `swift test` must be green again before the re-review.
  timestamp: 2026-08-19T13:04:36.617058+00:00
- actor: claude-code
  id: 01m0d23j6za9569m5x7bgerxaq
  text: |-
    Picked the card back up in `doing` for the one open finding.

    Audit of the whole file, not the one line. `ScenarioRunner.swift` builds a `ScenarioCheck` at 9 sites. Six take their `name:` from a file-scope constant in the block that starts at `validAnswerCheckName`. Three write the name as a string literal at the grading site:

    - `name: "pendingEnvelope"` in `runElevationIntegrationScenario`
    - `name: "answerNotInvalidated"` in `answerChecks(_:containsOneOf:mustNotContain:)`
    - `name: "noBackgroundRunsAfterRespond"` in the in-band canary grading function — the line the finding names

    So the finding names one instance of three. The other two are older than the rename; the rule the finding states — every check name the runner grades comes from a named constant declared with its siblings — does not exempt them, so all three go.

    Cross-file check before touching anything: no file outside `ScenarioRunner.swift` spells any of the three names. `ScenarioGradingTests.swift` reads checks back by constant only (`validAnswerCheckName`, `groundedCheckName`, `inBandCollectionCheckName`, `noBackgroundRunsAtAnswerCheckName`, `nestedCallEnteredCheckName`, `nestedGenerationReturnedCheckName`), and `ScenarioRunner.swift` itself matches `$0.name == validAnswerCheckName` when it fills `isValidAnswer`. No string value changes, so no transcript field and no graded outcome moves.
  timestamp: 2026-08-19T13:06:56.863579+00:00
- actor: claude-code
  id: 01m0d2s8ehrj8qfnxe1n9psmgs
  text: |-
    Finding closed, and closed against the whole file rather than the one line.

    Three constants added to the sibling block, each with a doc comment in the block's own voice ("The label of the check that grades …"):

    - `answerNotInvalidatedCheckName` = `"answerNotInvalidated"`, beside `validAnswerCheckName` — both come out of `answerChecks`.
    - `pendingEnvelopeCheckName` = `"pendingEnvelope"`, for the elevation runner.
    - `noBackgroundRunsAfterRespondCheckName` = `"noBackgroundRunsAfterRespond"`, beside `noBackgroundRunsAtAnswerCheckName` — the pair now reads as a pair.

    All nine `ScenarioCheck` sites in the file now take `name:` from a constant. No string value changed, so no `SCENARIO` line, no transcript field and no graded outcome moves — which is why the gated run at `f0cdc3e` still stands.

    One more copy of the same defect, found by the audit and removed with it: the `inBandCollection` failure message spelled `noBackgroundRunsAtAnswer` as literal text inside the message, so the constant's value was restated at a site the constant did not reach. It now interpolates `\(noBackgroundRunsAtAnswerCheckName)`. The rendered message is byte-identical; only the source stops holding a second copy.

    Not changed, and each for a reason that is a fact rather than a preference:

    - Doc comments and `//` comments that name a check (`inBandCollection`, `noBackgroundRunsAtAnswer`) in prose. A comment cannot interpolate, so there is no form of those lines that reads the constant. They are documentation about the check, not the value the runner grades.
    - Router symbols: `ParkedRun`, `ToolContext.parkedRuns()`, `RoutedSessionActor.parkedRunDrainRoundLimit`, `settleParkedRuns` — untouched by this diff.
    - The `PARKED-DRAIN [parkedRunDrain] …` quoted block and its explaining comment — untouched.
    - Genuine-suspension prose — untouched.
    - `Sources/` — untouched.

    Verification: `swift build --build-tests` complete, no compiler warnings or errors (the one `warning:` line is SwiftPM's build-planning note about the third-party mlx-swift resource bundle, the same note every prior run on this card recorded). `swift test` — 361 tests / 30 suites and 59 tests / 11 suites, all passed, exit 0.
  timestamp: 2026-08-19T13:18:47.761171+00:00
- actor: claude-code
  id: 01m0d2sewv9tqs1egjw6wd2nrv
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift. `swift build --build-tests` complete, zero warnings from this repo's code; `swift test` — 361 tests / 30 suites and 59 tests / 11 suites, zero failures.
    - next: /review. The gated suite was not re-run, and does not need to be: no string value changed, so no wire value and no graded outcome moved, and the gated green at f0cdc3e stands.
  timestamp: 2026-08-19T13:18:54.363090+00:00
- actor: claude-code
  id: 01m0d2vjfa8rqzgtjx5fxdnz4z
  text: |-
    ### test — green
    - evidence: `swift build --build-tests` — build complete; only the expected third-party mlx-swift resource-bundle build-planning note. `swift test` — 361 tests in 30 suites passed (3.938s); 59 tests in 11 suites passed (0.013s). 0 failures, 0 warnings from this repo's own code, 0 skipped.
    - next: none — ungated suite is clean.
  timestamp: 2026-08-19T13:20:03.562157+00:00
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

- [x] No check name, evidence field, or test name in the integration target calls running work "parked" or names a "run plane"
- [x] Every Router symbol is still spelled as Router spells it
- [x] The `PARKED-DRAIN` mirror is either intact or moved whole, and the choice is stated in a comment
- [x] Genuine-suspension prose is untouched

## Tests

- [x] Ungated `swift test` green, both targets
- [x] One gated run green, with the new check names read back out of the transcript

## Review Findings (2026-08-19 08:00)

> Scope: `review sha f0cdc3e~1..f0cdc3e` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift:1396` `completeness/invariant-propagation` — Check name is hardcoded as a string literal, violating the established pattern where all check names in this module use named constants. Lines 1360, 1369, and 1382 in the same function all reference check names through constants (e.g., `noBackgroundRunsAtAnswerCheckName`), but line 1396 hardcodes the string `"noBackgroundRunsAfterRespond"` directly. Add a constant definition after line 815: `let noBackgroundRunsAfterRespondCheckName = "noBackgroundRunsAfterRespond"`, then update line 1396 to use it: `name: noBackgroundRunsAfterRespondCheckName,`.
