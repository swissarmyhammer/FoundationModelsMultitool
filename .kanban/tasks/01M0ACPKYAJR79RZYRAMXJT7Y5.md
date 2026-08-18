---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: plan.md M9 still teaches the bare LanguageModelSession wiring the host contract does not name
---
`^260yggp` moved the shipped CLI onto the host contract — vended tools mounted on a `RoutedSession`, one turn drained through `streamEvents(to:)` — and updated `README.md`, which the card named. `plan.md` was not in that card's scope and still teaches the retired wiring:

    plan.md:344   (`makeMLXLanguageModel(for:)` + `runDemo`, which passes no session
    plan.md:403   let mlxModel = makeMLXLanguageModel(for: profile.standard)   // MLXLanguageModel: .toolCalling over the resident weights

`makeMLXLanguageModel(for:)` no longer exists. `README.md` points a reader at `plan.md` for "full design and milestone-by-milestone rationale", so a reader who follows that pointer lands on the exact wiring the contract rules out — the failure `^260yggp` was filed against, one document over.

## What to decide

`plan.md` is a historical milestone record, so the fix is not automatically "rewrite it". Either:

- correct the M9 sections so the plan states the shipped design, or
- mark the passage as superseded, naming what replaced it.

Pick one and apply it consistently to both sites.

## Acceptance Criteria

- [ ] `plan.md` names no symbol that does not exist
- [ ] A reader following `README.md` to `plan.md` gets the `RoutedSession` + `streamEvents(to:)` contract, or an explicit note that the passage is superseded
- [ ] Ungated `swift test` green (documentation-only change)