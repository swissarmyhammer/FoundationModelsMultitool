---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5fm5w0mr4hb8ayj1s0kzej7
  text: |-
    Research: GraphQLReply (Fixtures/GraphQLReply.swift) is a superset of the private `Reply` in SnapshotsGraphTests: same data/codes/rewrites, list/object/isNull, plus messages and rewrote(_:to:). No extension of the shared helper needed.

    Implementation: deleted the private `Reply` struct; run/checkpoints/checkpoint/rollback now return `GraphQLReply`; the alias test's `rewrites.map{...}.contains(["rollback","rollbackTimeline"])` became `reply.rewrote("rollback", to: "rollbackTimeline")`, which checks the same thing. Wrapped the `GraphQLReply(json:)` call in `run` so the line stays within 120 columns. No other assertion changed.

    Full `swift test`: 2685 tests in 228 suites passed, and the SnapshotsGraphTests suite passed. The only warning is SwiftPM's build-graph `missing creator for mutated node` on .build/.../mlx-swift_Cmlx.bundle. This change does not touch it, and earlier ledgers record it too.
  timestamp: 2026-10-21T16:19:44.788464+00:00
- actor: claude-code
  id: 01m5fm5xmdzzcjd8gvj8yb9j07
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift (+3/-57 net, private Reply removed); swift test: 2685 tests / 228 suites passed
    - next: /review
  timestamp: 2026-10-21T16:19:46.445154+00:00
- actor: claude-code
  id: 01m5fmb94e39ffaxkcew4y8hz1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (519cfaf) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed; 1 file reviewed (SnapshotsGraphTests.swift), 2 .kanban files excluded by .reviewignore. Subtask verified: `swift test --filter SnapshotsGraphTests` — 23 tests in 1 suite passed; the only assertion edit swaps the hand-built rewrites check for `reply.rewrote("rollback", to: "rollbackTimeline")`, same pair, as the task prescribes. Subtask checked.
    - next: none — task moved to done.
  timestamp: 2026-10-21T16:22:42.062400+00:00
- actor: claude-code
  id: 01m5fmbnhg0cv2dns42m8z0xqy
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — SnapshotsGraphTests.swift (+7/-58)
    - test: green — swift test, 2685 tests / 228 suites (run by implement)
    - commit: 519cfaf
    - review: clean — 0 findings
  timestamp: 2026-10-21T16:22:54.768819+00:00
position_column: done
position_ordinal: ffffffb780
title: 'SnapshotsGraphTests: read responses with the shared GraphQLReply fixture'
---
## What
^9c0fp9m added `Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift` (the `data`, the error codes and `extensions.rewrites` of one response). `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift` still holds its own private `Reply` struct with the same reading code. Replace it with `GraphQLReply` (its `rewrote(_:to:)` covers the alias case) and delete the private copy, so one reader stays.

## Tests
- [x] `swift test --filter SnapshotsGraphTests` passes with no change to an assertion. #graphql