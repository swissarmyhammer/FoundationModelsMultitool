---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m26rxtpx7rqgzbxzk628h7cb
  text: |-
    Research, before the edit. I read all five gated discovery suites and their shared support file, and I looked for the newest measured numbers in the board record.

    - The newest gated run stands in a comment of card `^wn02m4` (commit c4d586c, 2026-09-10 22:46 UTC): "agentSurfaceDiscovery 19 correct and 3 wrong in each of 3 rounds; heldOutSurfaceDiscovery 16 and 2 in each of 3 rounds; retrievalTextChoice unchanged; noDescription and overBudget pass."
    - `AgentSurfaceDiscoveryTests` says 19 correct of 25 and 3 undeclared in each round. That agrees with the newest run, so it is not stale.
    - `RetrievalTextSurfaceDiscoveryTests` and `Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift` carry the settling numbers of commit 2d3b21b, which came after the description rewrite at f5e895c, and the newest run reads them as unchanged. They are not stale.
    - `NoDescriptionSurfaceDiscoveryTests` and `Support/DiscoveryGrading.swift` make no count claim that a run can make stale.
    - `OverBudgetSurfaceDiscoveryTests` says the nine-entry surface assembles a prefix of about 7,600 characters. That number was read on card `^46j5hqw` (commit 8a8e4ba), before card `^p06rh7z` wrote the nine descriptions again at f5e895c. The prefix is built from those descriptions, so the number cannot still be 7,600. The board holds no newer reading of it.
  timestamp: 2026-09-10T23:02:28.829691+00:00
- actor: claude-code
  id: 01m26ry7n555ftpypv3cvem9wh
  text: |-
    ### implement — changed
    - evidence: I corrected 3 stale claims in 2 files, and changed no test, no assertion and no level. `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/HeldOutSurfaceDiscoveryTests.swift` (2): the paragraph beside `heldOutRoundCorrectLevel` said the suite is red at 9 of 22 with 8 undeclared paths and six queries that find nothing — it now says all three rounds score 16 of the 22 declared paths with 2 undeclared, that every query finds a declared path, and that the suite passes, measured 2026-09-10; the red result stays as history, named as the defect the group was written to find, and card `^p06rh7z` is named as the cause that moved it, because it wrote the nine tool descriptions again so that each names the work a person brings — the queries, the declared paths and the level did not change; and the time-limit paragraph said the run took 32.6 s, which is now 40.3 s from the recorded pass. `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/OverBudgetSurfaceDiscoveryTests.swift` (1): the claim that the nine-entry surface assembles a prefix of about 7,600 characters is dated to card `^46j5hqw`, which read it before the descriptions were written again; the doc now points a reader at the size each run prints, and keeps the true claim that the surface stays far under the budget. The level decision is written in the file: `heldOutRoundCorrectLevel` stays at 15, because the number comes from the shape of the group — one declared path for each of the fifteen queries — and not from the score of one model on one day; two runs on 2026-09-10 scored 16 in every round, so a later card can lift it to 16 on that record, and it is never lowered. The suite doc comment of `HeldOutSurfaceDiscoveryTests` makes no red claim, so it needed no change. `AgentSurfaceDiscoveryTests` (19 correct, 3 wrong), `RetrievalTextSurfaceDiscoveryTests`, `NoDescriptionSurfaceDiscoveryTests` and `Support/DiscoveryGrading.swift` agree with the newest run, so I corrected nothing in them. Tests: `swift test` at the root — 1423 tests in 114 suites passed, no warning. `swift build --package-path IntegrationTests --build-tests` — build complete, no compiler warning. I did not run the live suites again: this card changes comment text only, and comment text alters no measured value.
    - next: review
  timestamp: 2026-09-10T23:02:42.085095+00:00
- actor: claude-code
  id: 01m26s06vr2awpw3k99ejsmt3m
  text: |-
    ### commit — changed
    - evidence: 60b5c31 — 6 files changed, 93 insertions(+), 19 deletions(-)
    - next: no more steps set for this task; a person can move the card and push when ready
  timestamp: 2026-09-10T23:03:46.808197+00:00
- actor: claude-code
  id: 01m26s7mdyzgqvzbta1z34g5rq
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` with the local engine over commit 60b5c31 — 0 findings, 0 confirmed, 0 refuted, 7 validator runs, 0 failed. It read the 2 changed Swift files; it did not read the 4 `.kanban/` files, which an ignore rule holds out. No `## Review Findings` section stood on the card before this pass, so no earlier item is open. I checked the first three acceptance items: no doc comment of `HeldOutSurfaceDiscoveryTests.swift` says the suite is red today, because the 9-of-22 result stands there as history; the paragraph beside `heldOutRoundCorrectLevel` carries the new measurement of 16 of 22 with 2 undeclared paths, the date 2026-09-10, and card `^p06rh7z` as the cause; and the decision to keep the level at 15 stands in the file with its reason. The test item stays open, because commit 60b5c31 changes doc comment text only and card `^kvefc5z`, not this card, made the recorded run.
    - next: none. The card moves to done.
  timestamp: 2026-09-10T23:07:50.078197+00:00
- actor: claude-code
  id: 01m26s87wm4zaq3n21e3w70r8n
  text: |-
    ### finish iteration 1 — clean

    - implement: changed, in doc comment text only. Three old claims are corrected in two gated test files. No test, no assertion and no level changed.
    - test: green. `swift test` gives 1423 pass in 114 suites, no warning. The nested test target compiles with no warning. The live suites were not run again, because a comment change alters no measured value.
    - commit: 60b5c31, 6 files.
    - review: clean. 0 finding over `HEAD~1..HEAD`. The task moved to done. Three of the four items are checked. The fourth asks for a gated run, and this card cannot move a measured value, thus card `^kvefc5z` owns that reading.
  timestamp: 2026-09-10T23:08:10.004649+00:00
position_column: done
position_ordinal: ffc280
title: HeldOutSurfaceDiscoveryTests still says it is red at 9 of 22, and it now scores 16 and passes
---
## What

`heldOutRoundCorrectLevel` in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/HeldOutSurfaceDiscoveryTests.swift` carries this paragraph:

> **This level is the standard the surface owes a host, and the model does not meet it today.** ... Measured on 2026-09-10, all three rounds scored 9 of the 22 declared paths and returned 8 undeclared ones, and six queries found no declared path at all in any round. The suite is therefore red on a real, repeating defect, recorded on card `^kn9ay20`, and the level is not lowered to the measurement to make it green.

That is no longer true. Measured on 2026-09-10 while card `^kvefc5z` ran the gated suites:

    RESULT [heldOutSurfaceDiscovery] round=1 queries=15 correctTotal=16 wrongTotal=2
    RESULT [heldOutSurfaceDiscovery] round=2 queries=15 correctTotal=16 wrongTotal=2
    RESULT [heldOutSurfaceDiscovery] round=3 queries=15 correctTotal=16 wrongTotal=2

All three rounds scored 16 of 22 declared paths, over the level of 15, with 2 undeclared paths, and the suite passed in 40.3 s. Every query found a declared path, so the six queries the paragraph names as finding nothing now find something.

The most likely cause is card `^p06rh7z`, which rewrote all nine tool descriptions so each one names the work a person brings. That is what both the selection prompt and the retrieval tier read.

A doc comment that says a green suite is red is worse than no comment: a reader who trusts it will not believe a real failure later.

## What to do

- Read the paragraph beside `heldOutRoundCorrectLevel` and state what the measurement now is, with the date and the cause.
- Decide whether the level of 15 stands or rises. Three rounds each scored 16. A level at 16 would sit at the measurement, which is what `agentSurfaceRoundCorrectLevel` does and what that constant's own paragraph argues for. Say which, and why.
- Check the suite-level doc comment of `HeldOutSurfaceDiscoveryTests` for the same claim.
- Do not lower any level.

## Acceptance Criteria

- [x] No doc comment of the file says the suite is red.
- [x] The paragraph carries the new measurement, its date, and the card that most likely moved it.
- [x] The level decision is written down with its reason.

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel --filter HeldOutSurfaceDiscoveryTests`: passes, with the counts recorded on the card.

This item stays open. Commit 60b5c31 changes doc comment text only. It changes no test, no check and no level, so the work of this card cannot move a measured value. The card holds the counts of a pass of this filter — 16 correct and 2 wrong in each of three rounds, in 40.3 s — but that run came from card `^kvefc5z`, and not from this card. A person who wants this card to hold its own run must run the gated suite again.

#discovery #search-tools #documentation

## Review Findings (2026-09-10 19:04)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)
