---
assignees:
- claude-code
depends_on:
- 01M5F22CW6973NQR15P8B9JWYH
position_column: todo
position_ordinal: 8c80
title: 'SnapshotsGraph: checkpoints of a closed session through timelineCheckpoints (MT-13)'
---
## What
Today `checkpoints(sessionId:)` and `checkpoint(sessionId:index:)` in `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift` return empty or null for a session whose key is closed. Hooks 80e0250 adds `SnapshotStore.timelineCheckpoints(sessionKey:) async throws -> [Checkpoint]`. It is a read-only, on-disk read with no owner. It works on both open and closed keys, and for an open key it returns the same list as `checkpoints(sessionKey:owner:)`.

Switch the graph's read path (not the agent-facing `tools.snapshots.list` verb) to `timelineCheckpoints`, so the timeline of an archived or closed session is visible to the UI. Map `SnapshotError.noTimeline` to an empty list. Map `.unreadableTimeline` and `.invalidSessionKey` to CodedErrors, reusing the codes from the diffs task 01M5F22CW6973NQR15P8B9JWYH.

## Acceptance Criteria
- [ ] `checkpoints(sessionId:)` returns the checkpoints of a key that was opened, snapshotted and released
- [ ] `checkpoint(sessionId:index:)` works on a closed key
- [ ] A key with no timeline gives `[]`, not an error

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift`: against a real store in a temp dir, release the key, then query `checkpoints` and `checkpoint`
- [ ] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #snapshots