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
position_column: doing
position_ordinal: '80'
title: 'SnapshotsGraphTests: read responses with the shared GraphQLReply fixture'
---
## What
^9c0fp9m added `Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift` (the `data`, the error codes and `extensions.rewrites` of one response). `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift` still holds its own private `Reply` struct with the same reading code. Replace it with `GraphQLReply` (its `rewrote(_:to:)` covers the alias case) and delete the private copy, so one reader stays.

## Tests
- [ ] `swift test --filter SnapshotsGraphTests` passes with no change to an assertion. #graphql