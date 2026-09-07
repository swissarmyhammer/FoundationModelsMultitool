---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1ynvrmqkyf1nvmv8wh18sa0
  text: |-
    Research: read the three passages in `plan.md` and the true reason for `--no-parallel`.

    The reason for `--no-parallel` is in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift`, in the doc comment above `let liveProfileTurnstile = ConcurrencyGate()`. It says the reason is NOT GPU contention and NOT a Router residency limit. The turnstile is a test-suite rule: it admits one live scenario at a time because concurrent generation destroys grounding (`CLISmokeTests.swift` records that measurement). Swift Testing starts a test `.timeLimit` when the test starts, and each scenario takes the turnstile from inside its own test body, so a parallel run spends the limit on queue time. The requirement stands; only its stated cause was wrong.

    So the `--no-parallel` paragraph keeps the requirement and now names the turnstile as the cause, and says plainly that the turnstile is a test-suite rule, not a Router limit.

    Discovery for a new card: `IntegrationTests/Package.swift` carries the same stale claim in a doc comment — "queues behind `liveProfileTurnstile` for the one resident live profile". This card is documentation only and permits no Swift code change, so that line is left alone and recorded as new work.
  timestamp: 2026-09-07T19:34:59.991510+00:00
- actor: claude-code
  id: 01m1ynwgjeramy4zfcyrf91yy9
  text: |-
    ### implement — changed
    - evidence: 1 file — plan.md. Three passages corrected: the retired-passage summary (`RoutedLLM` slots now read "residency is pooled and reference-counted, so more than one profile can be resident"), the librarian paragraph ("of that same profile" in place of "of the one resident profile"), and the `--no-parallel` paragraph (the reason is now the suite's own `liveProfileTurnstile` and grounding, with an explicit note that the turnstile is a test-suite rule, not a Router limit). No Swift code changed.
    - runs: `swift build` clean; `swift test` green — 1401 tests in 109 suites, 0 failures. The integration package was not run: a plan.md change cannot alter executable behavior.
    - new work: `^` new card 01M1YNW6M4VHYNEMFV7GZ6MQJ1 for the same stale claim in `IntegrationTests/Package.swift`, which this card forbids me to touch.
    - next: /review
  timestamp: 2026-09-07T19:35:24.494882+00:00
- actor: claude-code
  id: 01m1yp2aa6yrq6ag2rdm8q1h6s
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 93fa29a) — zero new findings; 0 confirmed, 0 refuted. No prior Review Findings section. `plan.md` matched no validator; `.kanban/` files excluded by `.reviewignore`.
    - acceptance: the change corrects all three passages. A grep of `plan.md` for "one resident", "resident at a time" and "the one resident" gives no match, so no claim of one resident profile is left. The `--no-parallel` paragraph now gives a reason that is true for pooled residency: the scenarios queue behind the suite's own `liveProfileTurnstile`, and the text states the turnstile is a test-suite rule, not a Router limit. The change touches `plan.md` only, so there is no Swift code change.
    - next: task moved to done.
  timestamp: 2026-09-07T19:38:34.694922+00:00
- actor: claude-code
  id: 01m1yp32dje8n9pwznzdq6wkt0
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (plan.md); the three remaining single-residency claims are corrected, and the --no-parallel requirement stays with a true reason
    - test: green — swift test 1401 tests in 109 suites passed; the integration package was not run, because the change touches only plan.md
    - commit: 93fa29a
    - review: clean — zero new findings; task moved to done
  timestamp: 2026-09-07T19:38:59.378246+00:00
position_column: done
position_ordinal: ffb580
title: plan.md still claims one profile is resident at a time, but residency is pooled
---
## What

Card `^w67g119` corrected the Router surface summary in `plan.md`: residency is pooled and owned by ARC, and the next `resolve` drains the pending evictions before it measures the host budget. Confirmed against the vendored router source, `LanguageModelProfile.swift`: "Residency is pooled. The `Router` reference-counts each resident model across profiles."

`plan.md` keeps the older, single-residency claim in three more places that card `^w67g119` did not name. None of them names the deleted `release()`, so they passed that card's acceptance criteria, but they now contradict the corrected summary:

- The retired-passage summary near the end of the file — "a resident `LanguageModelProfile` with `standard`/`flash` `RoutedLLM` slots (one profile resident at a time)".
- The librarian paragraph — "the one resident profile".
- The live-suite paragraph on `--no-parallel` — "every scenario queues for the one resident live profile". Check this one with care: the reason to keep `--no-parallel` may still be correct even when more than one profile can be resident, so the sentence may need a new reason and not only a new fact.

## Acceptance Criteria

- [ ] `plan.md` makes no claim that only one profile is resident at a time.
- [ ] The `--no-parallel` paragraph gives a reason that is true for pooled residency.
- [ ] No Swift code changes. This card is documentation only.

## Tests

- [ ] None. `plan.md` carries no executable content, so `swift test` is unaffected. #router #tech-debt #docs