---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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