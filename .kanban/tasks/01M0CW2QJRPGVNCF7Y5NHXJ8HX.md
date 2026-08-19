---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0dn62xkazm7j7wg2trd9txs
  text: |-
    Picked up. Research results, before any edit:

    - The env-var gate is gone. The suite is in the nested package `IntegrationTests/`. The card text "gated run" now means a run of that package.
    - The check names moved to the new vocabulary: `noBackgroundRunsAtAnswerCheckName`, `noBackgroundRunsAfterRespondCheckName`, `inBandCollectionCheckName` in `Support/ScenarioRunner.swift`. The card's `runPlaneEmptyAtAnswer` names are the old spellings of the same checks.
    - `runInBandCollectionCanaryScenario` mounts the surface through `makeScenarioSurface(over:on:)`, which builds a plain registry and mounts `makeSessionTools(librarian: fixture.profile.flash)`. `CLIRunner.runDemo` applies `registry.directMode()` before the same mount call and keeps the same `librarian:` argument. The direct-mode shape must mirror that wiring.
    - `inBandCollectionChecks(for:answerContainsOneOf:groundedIn:)` already grades the full set the mechanism shape needs: validAnswer, grounded, inBandCollection, noBackgroundRunsAtAnswer, noBackgroundRunsAfterRespond. `ScenarioGradingTests` covers that function without a live model. I keep its signature, so both shapes and the ungated grading tests use one rule.
    - `WaitTool` with no timeout waits for the run to settle (`absentTimeoutWaitsForTheRun`). A tool body that sleeps a few seconds gives a genuinely deferred settlement, because `runCode` backgrounds every call at once (`MultiTool.detachmentClocks` answers a zero wait clock).
    - Measurements for the ceiling: local run 2026-08-19 (card ^dwzkfzx): canary suite 368.491s, whole run 950.159s. CI run 32203706380: whole run 4214s, canary killed at its 600s limit, ten other suites green. Worst healthy local pass on record: 445.5s (commit 00a1066 set: 445.5 / 327.2 / 113.0).

    Plan: add `IntegrationDelayedEchoTool` (scenario 9) to `Fixtures/ScenarioTools.swift`; add a `direct:` parameter to the canary runner and to `makeScenarioSurface`; rewrite `InBandCollectionCanaryTests` into a mechanism test (direct mode, per-run nonce) and the unchanged teaching test; re-derive the ceiling from the CI measurement.
  timestamp: 2026-08-19T18:40:22.451305+00:00
- actor: claude-code
  id: 01m0dnkfk3vfgr70thze7f05c0
  text: |-
    Ceiling derivation, as the card requires. The 600-second ceiling is re-derived, not raised, and the new value is 62 minutes.

    **The measurements.**
    - Local run 2026-08-19 (card ^dwzkfzx): the canary suite took 368.491s of a 950.159s whole run. The other ten suites took 581.668s.
    - CI run 32203706380: the whole run took 4214s. The canary was cut at its 600s limit — the run's only failure. The other ten suites took about 3614s.
    - Worst healthy local pass on record: 445.5s (the commit `00a1066` set: 445.5 / 327.2 / 113.0).

    **The derivation.**
    1. The same ten suites cost 3614s on the CI runner against 581.7s on the dev box. The ratio is 6.21.
    2. Project the canary onto the CI runner: 368.5s x 6.21 ≈ 2289s for the latest pass; 445.5s x 6.21 ≈ 2768s for the worst healthy pass on record.
    3. Apply the trait's own margin rule — clear the worst observed run by about one third: 2768s x 4/3 ≈ 3690s. Round up to whole minutes: 62 minutes.

    **Why this is a re-derivation and not a raise.** The old ten-minute value came from the same margin rule (445.5s x 4/3 ≈ 594s), applied only to dev-box measurements. The CI run showed a healthy canary needs about 2300-2800s on that runner, so 600s sat below a healthy run and reported hardware as a defect. A ceiling is a hang detector; it must clear every healthy run on every machine that runs it. A genuine runaway still reports in about an hour, where no limit at all would wait for the CI job timeout.

    **Why not remove it.** Removal leaves a true hang bounded only by the CI job timeout (hours) and leaves a local hang unbounded. The derived value keeps the detector and stops the misattribution.

    The full derivation, and both earlier measurement eras, stay in the trait comment on `InBandCollectionCanaryTests`. The limit applies to each test in the suite; the mechanism test has no recorded runs yet, so its own tighter ceiling waits for its first measured times.
  timestamp: 2026-08-19T18:47:41.411923+00:00
- actor: claude-code
  id: 01m0dnmcttvfmnh0btqvb0xtnv
  text: |-
    ### implement — changed
    - evidence: 4 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift (scenario 9: `IntegrationDelayedEchoTool`, `integrationDelayedEchoDelay` = 4s, per-run `integrationDelayedEchoNonce()`, `IntegrationScenarioGrounding.delayedEcho`), IntegrationTests/.../InBandCollectionCanaryTests.swift (two tests: `theDelayedEchoRoundTripsThroughItsHandle` in direct mode with a fresh nonce, and the unchanged teaching test `theModelCollectsItsOwnBackgroundRun`; `.timeLimit(.minutes(62))`, re-derived — see the derivation comment above), IntegrationTests/.../Support/ScenarioRunner.swift (`direct:` parameter on `runInBandCollectionCanaryScenario` and `makeScenarioSurface`, mirroring `CLIRunner.runDemo`'s `--direct` mount), IntegrationTests/.../ScenarioFixtureTests.swift (two new ungated premise tests, written first and watched fail to compile before the fixture existed).
    - proof: `swift build --package-path IntegrationTests --build-tests` clean (only the known `mlx-swift_Cmlx.bundle` build-system message, on record at ^akpzysf). Root `swift test`: 361 tests in 30 suites passed, 0 failures. Integration package no-model suites: 50 tests in 3 suites passed, including the delayed-echo premise test (4.255s — the delay is real) and the fresh-nonce test.
    - not run, per instruction: the real-model suites. The two remaining Tests checkboxes wait for that run.
    - unchanged on purpose: `inBandCollectionChecks` and every check name, so `ScenarioGradingTests` still covers the grading rule; the teaching test's fixture, prompt, surface and grading; every other suite's assertions.
    - next: `/review`; then the orchestrator schedules `swift test --package-path IntegrationTests --no-parallel` and records both shapes' times here.
  timestamp: 2026-08-19T18:48:11.354278+00:00
- actor: claude-code
  id: 01m0dp2rmw42r19z11fm6p25n5
  text: |-
    ### test — green
    - evidence 1: `swift test` (repo root, ungated). Result: 361 tests, 30 suites. All tests pass. 0 failures. 0 skips. Time: 3.981s.
    - evidence 2: `swift test --package-path IntegrationTests --no-parallel --filter InBandCollectionCanary` (single command, real 27B model). Result: 2 tests, 1 suite. All tests pass. 0 failures. 0 skips.
      - Test "the delayed echo's value comes back through its handle, collected in band" (mechanism shape, `delayedEchoMechanism`): PASS. Time: 220.758s.
      - Test "the model collects its own background run, and the turn ends with nothing still running" (adversarial teaching shape, `inBandCollection`): PASS. Time: 157.465s.
      - Suite total time: 378.223s.
    - note: the build showed one line, `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/...)`. This is the known third-party build message tracked by task 01M0ABSV0JS6YRK2Z7RAKPZYSF. It does not count as a test warning.
    - next: run the full gated CI pass and record the canary's time against the 4214s whole-run baseline from run 32203706380.
  timestamp: 2026-08-19T18:56:02.204139+00:00
- actor: claude-code
  id: 01m0dpdasyh5heqenjhqd36ynx
  text: |-
    ### review — findings
    - evidence: 1 finding — `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift:866` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
    - scope: review sha HEAD~1..HEAD (commit cf55b56); counts: findings 1, confirmed 1, refuted 0
    - next: correct the finding across the full file, then run the review again. The task stays in review.
  timestamp: 2026-08-19T19:01:48.478860+00:00
- actor: claude-code
  id: 01m0dpe5tm1c0avepxjcqe3p5z
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files: delayed-echo fixture, two-shape canary, direct-mode runner, premise tests
    - test: green — root 361/30; canary filter run 2/1: delayedEchoMechanism 220.758s, inBandCollection 157.465s
    - commit: cf55b56
    - review: findings — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift:866 (magic numbers)
  timestamp: 2026-08-19T19:02:16.148459+00:00
- actor: claude-code
  id: 01m0dppa7fta8yh06xwm437vfy
  text: |-
    ### implement — changed
    - evidence: 1 file — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift. The finding: `ScenarioTools.swift:866` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants. The cause: the literal `4` was an argument in `.seconds(4)`. The rule reports a literal in an argument position. The fix: a new named constant `integrationDelayedEchoDelaySeconds = 4`, with a document comment. `integrationDelayedEchoDelay` now reads that constant. The rule does not report a literal that a declaration names directly, so this shape is correct.
    - audit: I examined all code this task added to the file — the delayed-echo fixture and the nonce helper. `integrationDelayedEchoNonceLength = 12` names its value directly; the rule accepts it. All other numeric references read named constants. No other unnamed numeric literal remains.
    - build: `swift build --package-path IntegrationTests --build-tests` — clean. One known third-party message (`mlx-swift_Cmlx.bundle`, task ^akpzysf).
    - test: `swift test --package-path IntegrationTests --filter ScenarioFixtureTests` — 20 tests, 1 suite, all pass, 0 failures. The real-model canary did not run, as this step's instruction requires.
    - card: the finding's checklist item is now `- [x]` on the description.
    - next: run /review again. The task stays in doing.
  timestamp: 2026-08-19T19:06:42.799335+00:00
- actor: claude-code
  id: 01m0dpw9h0d3drzfg8am1heh01
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit cda247d) — 0 findings. 1 file reviewed, 4 files skipped by `.reviewignore` (`.kanban/`).
    - The prior finding `ScenarioTools.swift:866` `code-hygiene/magic-numbers-swift` is checked. No open findings stay.
    - Note: the "## Tests" item for a green gated CI run is a deliverable. It is not a review finding, and it does not block this review gate. The user must push the commit to start that CI run.
    - next: task moved to done.
  timestamp: 2026-08-19T19:09:58.688627+00:00
- actor: claude-code
  id: 01m0dpwvhrbckd42p10ygv2t8x
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — integrationDelayedEchoDelaySeconds names the delay literal in ScenarioTools.swift
    - test: green — root 361/30, 0 skipped; no-model integration suites 50/3
    - commit: cda247d
    - review: clean — 0 findings; task moved to done. The CI-run checkbox stays open until the user pushes.
  timestamp: 2026-08-19T19:10:17.144094+00:00
position_column: done
position_ordinal: d780
title: 'InBandCollectionCanary: test the background-run mechanism with a delayed echo, and split the teaching claim off it'
---
`InBandCollectionCanaryTests` exceeded its 600-second ceiling on CI run `32203706380` — the only failure in a run where the other ten suites passed. It is the most expensive suite in the target and it grades two unrelated things through one costly model loop.\n\nDesign worked out with the user 2026-08-19; the delayed-echo shape is theirs.\n\n## What the test actually checks, in plain terms\n\n`runCode` runs the tool call in the background and returns a handle. `wait(handle)` collects the result. Two different parties can do that collecting:\n\n- **the model**, by calling the mounted `wait` tool, or\n- **`RoutedSession.respond(to:)`**, which collects anything still outstanding when the call ends.\n\nBoth produce an answer that looks right, so `validAnswer` and `grounded` cannot tell them apart. The discrimination is `inBandCollection` (`waitCalls > 0`), `runPlaneEmptyAtAnswer` (nothing outstanding when the model's **first** turn ended) and `runPlaneEmpty`.\n\nSo the question under test is **who collected the result**, not whether the answer was right.\n\n## Two properties are bundled, and only one needs the expensive setup\n\n**A — the mechanism.** A tool call runs in the background, returns a handle, and the result comes back through that handle intact. Pure plumbing.\n\n**B — the teaching.** The prompt tells the model *not* to block. So the only thing that can make it call `wait` is the instruction carried on the handle itself, competing against the user's explicit request. The recorded run collected anyway, three times over, which is how strongly that in-band instruction outweighs the prompt. This is the evidence behind this package's \"in-band teaching beats upfront prose\" rule and behind `^466d38p`.\n\nThe current suite pays for a full discovery -> snippet -> background-run -> collect -> answer loop to establish a precondition, when everything it grades happens strictly after the handle is in the model's hands.\n\n## The current fixture never exercises \"later\"\n\n`IntegrationArchiveRebuildTool` returns **immediately** — it hands back the manifest code with no delay. The comment at `Fixtures/ScenarioTools.swift` says the delay was removed deliberately. But the model then has to generate a whole turn before it calls `wait`, and that takes seconds, so the result is always already available by the time anything collects it.\n\n**The suite named for deferred completion has never once collected a result that was not already finished.** `wait` returns instantly every time. The deferred path — a real deadline, a real wake-up — is untested.\n\n## What to build\n\n**A delayed echo tool.** Takes a value, returns a handle, and settles with that value a few seconds later. Prompt the model explicitly to call it by name and report what comes back. That gives:\n\n- a genuinely deferred completion, so `wait` must actually wait and be woken — more mechanism covered than today\n- exact grounding: echo a nonce the model has never seen, so the reply either carries it or it does not; no fixture constant and no grounding judgment\n- the shortest sequence that still passes through the real machinery — with `directMode()` there is no discovery at all: call the named tool, take the handle, `wait`, report\n\nThe delay costs wall-clock, not compute. That is the right trade: it buys real coverage of the deferred path while removing model turns.\n\n**Keep one adversarial run for B.** An explicit \"call it and wait\" prompt makes `inBandCollection` a test of the prompt, which is exactly what the current suite's own comment warns against: \"A prompt that asked the model to wait would make `inBandCollection` a test of the prompt; this one makes it a test of the product.\" So B keeps the \"do not block\" prompt. It just stops being something the everyday mechanism check has to pay for.\n\n`runPlaneEmptyAtAnswer` survives in both shapes — a model that ends its turn with work still outstanding fails it whatever the prompt said.\n\n## Do not\n\n- Do not raise the 600-second ceiling to make CI green. That hides a 70-minute run rather than fixing it.\n- Do not delete the adversarial prompt. It is the only evidence for the in-band teaching rule.\n- Do not use the old vocabulary in anything new here — see `^820xc9z`. Write the new tool and suite as background run / handle / collect, with states `running`, `complete`, `error`.\n\n## Open question for the run, not for the card\n\nWhether the delayed echo still needs the 27B. Its claim is protocol-following taught in-band, and a nonce echo is structurally impossible to hallucinate, which is a much weaker capability claim than `SearchThenCallTests` makes. Measure it against a smaller model rather than assuming either way — that is the `^ck74mtg` method.\n\n## Acceptance Criteria\n\n- [x] A delayed echo tool exists whose result genuinely settles after the handle is issued, so `wait` waits and is woken\n- [x] The everyday mechanism test drives the shortest sequence: named tool, handle, collect, report — no discovery\n- [x] Grounding is a nonce, so a hallucinated answer cannot pass\n- [x] The adversarial \"do not block\" run still exists and still grades `inBandCollection` against the instruction on the handle rather than against the prompt\n- [x] The 600-second ceiling is re-derived from measurement on the slowest machine that runs it, or removed as the wrong instrument — never simply raised\n\n## Tests\n\n- [x] Ungated `swift test` green\n- [x] Both gated shapes run green locally, per-suite times recorded here\n- [ ] A full gated CI run green, with the canary's time recorded against the 4214s whole-run baseline from `32203706380`\n

## Review Findings (2026-08-19 13:57)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Fixtures/ScenarioTools.swift:866` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
