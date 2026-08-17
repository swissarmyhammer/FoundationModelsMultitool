---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m07yg9hgjq24fa39kw42ag4r
  text: |-
    Picked up; moved to `doing`. Research before editing:

    **The probe has its own reason, already written down elsewhere.** `Fixtures/ScenarioTools.swift`, on `integrationNestedGenerationTokenLimit = 32`: "A cap this tight makes a live nested turn a matter of seconds, so the limit can only be reached by a call that is not running at all." That is the probe's own justification for a tight ceiling, native to this package, and the limit comment never cited it. It cited the canary instead.

    **The probe's own measurements are recorded in `Support/IntegrationGate.swift`.** Parked: 165.4s and 166.5s before Router's `^1zt7vyg`. Healthy: 28.1s in the `--no-parallel` timing table, "about 28s after it", and 16.4s on the Qwen pin against 26-28s on Muse. So the healthy band is well inside seconds-to-half-a-minute and 180s clears the worst of it by more than six times. The limit stays at three minutes.

    **No other suite borrows a peer's ceiling.** Checked every `.timeLimit` in the gated suites: `RespondDrainTests`, `SearchThenCallTests`, `AsyncFanOutTests`, `ElevationTests` and `PrefixReuseTests` each hold `.minutes(30)` with no comment at all, so they cite nothing. `InBandCollectionCanaryTests` now holds ten minutes and derives it from its own runs; it names the peers only to refuse them ("nothing here licenses raising their ceilings"). Nothing to note under the "other suites borrowing" constraint.

    **One more stale line in the same file, and it is in scope.** The suite doc says "It **fails today**, and that is honest — it will pass when the gate is fixed." Router's `^1zt7vyg` fixed the gate, and `IntegrationGate` records the probe returning since. Any limit reason drawn from post-fix times contradicts that sentence, so the two are corrected together. Same class of defect as the card: a sentence that was true when written and was never re-derived.

    Tree checked before editing: clean apart from kanban files (this card and another session's `^wnfzwxg`).
  timestamp: 2026-08-17T13:27:47.504932+00:00
- actor: claude-code
  id: 01m07z14mcyb265bgdfe2knwnz
  text: |-
    Implementation landed. One file changed: `Tests/FoundationModelsMultitoolIntegrationTests/NestedGenerationProbeTests.swift`, comments only.

    **The limit comment now stands on this probe's own evidence.** The word "canary" is gone from the file. The new comment says four things, in this order: no peer suite's ceiling is cited or is evidence here; the limit IS the detector, because a deadlock is reported by the limit being reached and not by any assertion the file makes, so the ceiling has to stay close above the expected runtime; a healthy run is short by construction, because `integrationNestedGenerationTokenLimit` caps the nested turn and that constant states the argument where it is set; and the recorded runs — parked at 165.4s and 166.5s, returned at 14.1s, 14.8s, 16.4s, 25.8s and 28.1s since Router's `^1zt7vyg`. 180s stands more than six times above the slowest run that came back, so a run that reaches the limit is parked rather than slow. The margin also has to cover the turnstile queue and the profile load, because the clock starts when the test starts (`IntegrationGate`).

    **The limit value did not move.** It is `.minutes(3)` before and after. The comment closes by saying so: "Nothing here raises a ceiling." That sentence is also the answer to `test-integrity/no-test-cheating`, whose "What else to check" item 3 is "a timeout raised instead of fixing the root cause".

    **One further edit, same file, same defect class.** The suite doc read "It **fails today**, and that is honest — it will pass when the gate is fixed." The gate is fixed, and a limit reason drawn from post-fix runs contradicts that sentence. It now reads "It **passes today**: Router's `^1zt7vyg` lends the permit to the nested turn instead of holding it, and this probe has come back on every run since."

    **Rules read before editing.** `dump validators` on the file returned 65 rules across nine validators; the whole dump was read. The ones that bear on a comment-and-doc edit: `no-test-cheating` item 3 above; `swift/documentation` (`///` only, backtick symbol references, what/why not how); `no-commented-code` (a block that reads as English is prose — the run figures are prose, not statements); and `complexity-swift`/`function-length-swift`, which report a finding when a doc line is inserted between a `// swiftlint:disable:next` directive and its target. This file holds no such directive, so the placement is safe. `magic-numbers-swift` would read the bare `3` the same way it reads the `10` and the `30` of every peer suite; the value is untouched, so this change neither creates nor resolves that.

    **Constraints honoured.** No assertion and nothing the probe tests was changed. `Package.swift` untouched (Router stays at aff8b1b). No gated `MULTITOOL_INTEGRATION` run.
  timestamp: 2026-08-17T13:36:59.532010+00:00
- actor: claude-code
  id: 01m07z1ajrbze9p9p17y81str5
  text: |-
    ### implement — changed
    - evidence: 1 file — /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Tests/FoundationModelsMultitoolIntegrationTests/NestedGenerationProbeTests.swift; `swift test` exit 0, 352 tests in 29 suites and 59 tests in 11 suites, zero failures, no source warning (the one `warning:` in the log is SwiftPM's pre-existing `missing creator for mutated node` for `mlx-swift_Cmlx.bundle`)
    - next: `/review`
  timestamp: 2026-08-17T13:37:05.624361+00:00
- actor: claude-code
  id: 01m07z5n8r9kb72e183ctkxghc
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 442115b) — 0 findings, 0 confirmed, 0 refuted; 9 validator passes attempted, 0 failed. 1 file reviewed: Tests/FoundationModelsMultitoolIntegrationTests/NestedGenerationProbeTests.swift. 4 .kanban files excluded by .reviewignore.
    - next: task moved to done. No gated MULTITOOL_INTEGRATION run was made; the change is comment-only.
  timestamp: 2026-08-17T13:39:27.640052+00:00
- actor: claude-code
  id: 01m07z6dx9r33kq05hm4kzpytc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file, limit comment rewritten to derive from the probe's own runs; `.minutes(3)` unchanged
    - test: green — `swift test`, 352 tests/29 suites and 59 tests/11 suites
    - commit: 442115b
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings, 9 validator passes, 0 failed; task advanced to `done`

    Closed in one iteration. The fix was not the number — it was that the reason had been borrowed from a suite measuring something else. The probe's limit *is* its deadlock detector, since nothing in the file asserts a deadlock and reaching the ceiling is how one gets reported; the canary's limit is headroom on a content-graded answer. They shared a number and nothing else, and the number turned out to be right on its own evidence: 180s is more than six times the slowest healthy run.

    The implementer also found and corrected a stale claim in the same doc comment — "It fails today ... it will pass when the gate is fixed" — which had been true when written and was falsified by Router's `^1zt7vyg` landing.

    It checked whether any other suite borrows a peer's reasoning and found none: the five 30-minute suites carry no comment on their limit, and `InBandCollectionCanaryTests` derives its ten minutes from its own runs.
  timestamp: 2026-08-17T13:39:52.873647+00:00
position_column: done
position_ordinal: c980
title: NestedGenerationProbeTests cites the in-band canary's limit as three minutes, and it has not been three for two changes
---
Found while re-deriving the canary's ceiling under `^wnfzwxg`. Not caused by that change, but that change widens the gap, so it is recorded rather than fixed in passing.

## The stale line

`Tests/FoundationModelsMultitoolIntegrationTests/NestedGenerationProbeTests.swift`, in the `@Suite` limit comment:

    // Three minutes, the in-band collection canary's limit and for its reason:
    // this is one tool call plus one short nested turn, so a live run belongs
    // in the same 40-90 second band its peers finish in.

The clause "the in-band collection canary's limit" is false. That canary went 3 to 15 to 8 minutes across the investigation on `^wnfzwxg`, and `^wnfzwxg` has now re-derived it to ten. The probe's own three minutes has not moved.

## Why this is worth a card rather than a one-line edit

The sentence does two things at once. It states a **number** the two suites once shared, and it borrows a **reason**. Only the number went stale.

The reason it borrows is still sound for the probe and is stated in its own next clause: the probe exists to catch a deadlock, a deadlock is reported by the limit being reached, so the limit must sit near the expected runtime. The canary no longer shares that property — it is graded on the content of an answer, not on whether a clock fired, and its ten minutes is headroom over a measured worst run rather than a deadlock detector.

So the fix is not to update "three" to "ten". It is to cut the borrowed authority and let the probe's three minutes stand on the reason that is actually its own, which the comment already gives.

## Acceptance Criteria

- [x] `NestedGenerationProbeTests` no longer cites the in-band collection canary's limit as its source
- [x] Its three-minute limit is unchanged, and the deadlock-reporting reason it already states is what carries it
- [x] `swift test` stays green

## Tests

- [x] Ungated `swift test` green; no gated run needed, since the change is a comment
