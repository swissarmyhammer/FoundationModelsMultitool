---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: IntegrationTests/Package.swift doc comment still claims one resident live profile
---
## What

Card `^s8e14a7` corrected the three remaining single-residency claims in `plan.md`. The same stale claim stays in a Swift doc comment.

`IntegrationTests/Package.swift`, in the comment that gives the reason for `--no-parallel`:

> every scenario here queues behind `liveProfileTurnstile` for the one resident live profile

Router residency is pooled and reference-counted, so more than one profile can be resident. The `--no-parallel` requirement itself stands: the turnstile admits one live scenario at a time because concurrent generation destroys grounding, and Swift Testing spends a test `.timeLimit` on queue time. Correct the cause; keep the requirement.

The same file, near the target dependency on `TestConcurrency`, says the gate "holds this target to one resident live profile". Check that line too.

## Acceptance Criteria

- [ ] `IntegrationTests/Package.swift` makes no claim that the Router keeps one profile resident at a time.
- [ ] The `--no-parallel` reason it gives is true for pooled residency.
- [ ] The `--no-parallel` requirement stays.

## Tests

- [ ] None. The change is a comment. `swift build` must stay clean. #router #tech-debt #docs