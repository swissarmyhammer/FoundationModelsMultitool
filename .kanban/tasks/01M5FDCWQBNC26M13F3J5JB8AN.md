---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: 'SnapshotsGraphTests: read responses with the shared GraphQLReply fixture'
---
## What
^9c0fp9m added `Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift` (the `data`, the error codes and `extensions.rewrites` of one response). `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift` still holds its own private `Reply` struct with the same reading code. Replace it with `GraphQLReply` (its `rewrote(_:to:)` covers the alias case) and delete the private copy, so one reader stays.

## Tests
- [ ] `swift test --filter SnapshotsGraphTests` passes with no change to an assertion. #graphql