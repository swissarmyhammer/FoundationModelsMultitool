---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g2t6j5crrxg7k12gqccjpr
  text: 'Research: the read path is `SnapshotsGraphResolver.timeline(of:context:)` in SnapshotsGraphSchema.swift, which calls owner-checked `store.checkpoints(sessionKey:owner:)` and turns `.unavailable` into nil (TODO HOOKS-5). `rollbackTimeline` does NOT use that helper: it has its own canSee + resolver guard and calls `store.rollback(sessionKey:owner:to:)`, so it stays owner-checked and NOT_FOUND for a released key without change. `store.timelineCheckpoints` and `store.diff` both go through `readStoredTimeline` (no owner); missing shadow dir/timeline -> `.noTimeline`, bad key -> `.invalidSessionKey` (thrown by `shadowDirectory`). Consequence: after a timeline conflict the owner is poisoned but the on-disk read still works, so the existing `aTimelineConflictGivesItsCodes` query expectation (SNAPSHOTS_NOT_AVAILABLE) changes — the poisoned-owner check moves to a second rollback. `aReleasedSessionGivesNothing` also flips (list/checkpoint now visible, rollback still NOT_FOUND).'
  timestamp: 2026-10-21T20:35:31.013880+00:00
- actor: claude-code
  id: 01m5g32ngs5xvs127f7rg2yrvv
  text: 'Implementation landed. `SnapshotsGraphResolver.timeline(of:context:)` now calls `store.timelineCheckpoints(sessionKey:)`; `.noTimeline` -> nil ([] / null); every other SnapshotError (incl. `.unreadableTimeline`, `.invalidSessionKey`) goes through the existing `SnapshotsGraphError.coded`. The canSee + resolver guard is unchanged. `rollbackTimeline` is untouched and still owner-checked via `store.rollback(sessionKey:owner:to:)`: a released key still gives NOT_FOUND (test `rollbackOfAReleasedSessionGivesNotFound`, which also checks the work tree did not change). `Checkpoint.changes` on a closed key works with no code change (store.diff is an on-disk read) — test `changesOfAReleasedSessionGivesTheDiffs`. Behaviour change worth knowing: after a timeline conflict the queries no longer give SNAPSHOTS_NOT_AVAILABLE; they read the on-disk timeline (3 checkpoints incl. the other store''s). `aTimelineConflictGivesItsCodes` now asserts SNAPSHOTS_NOT_AVAILABLE on a second rollback, and the new `aConflictedTimelineIsStillRead` covers the query side. `aReleasedSessionGivesNothing` was replaced by four released-key tests. `aKeyWithNoTimelineGivesNothing` passed before the change too (the old path turned `.unavailable` into []), so it is a regression guard, not a RED test. `tools.snapshots.list` verb unchanged. Golden schema unchanged.'
  timestamp: 2026-10-21T20:40:08.473530+00:00
- actor: claude-code
  id: 01m5g32rgk1899ez4tx332stma
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraphSchema.swift, Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift, Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift. RED: `swift test --filter SnapshotsGraphTests` 5 new tests failed for the expected reasons; GREEN: 36/36. `swift test --filter Snapshots` 81 tests in 4 suites passed; `swift test` 2707 tests in 229 suites passed, 0 failures. Only warning is SwiftPM's "missing creator for mutated node" on the mlx-swift_Cmlx.bundle dependency product, which exists independent of this change.
    - next: /review (task left in doing, not committed)
  timestamp: 2026-10-21T20:40:11.539337+00:00
depends_on:
- 01M5F22CW6973NQR15P8B9JWYH
position_column: doing
position_ordinal: '80'
title: 'SnapshotsGraph: checkpoints of a closed session through timelineCheckpoints (MT-13)'
---
## What
Today `checkpoints(sessionId:)` and `checkpoint(sessionId:index:)` in `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsGraph.swift` return empty or null for a session whose key is closed. Hooks 80e0250 adds `SnapshotStore.timelineCheckpoints(sessionKey:) async throws -> [Checkpoint]`. It is a read-only, on-disk read with no owner. It works on both open and closed keys, and for an open key it returns the same list as `checkpoints(sessionKey:owner:)`.

Switch the graph's read path (not the agent-facing `tools.snapshots.list` verb) to `timelineCheckpoints`, so the timeline of an archived or closed session is visible to the UI. Map `SnapshotError.noTimeline` to an empty list. Map `.unreadableTimeline` and `.invalidSessionKey` to CodedErrors, reusing the codes from the diffs task 01M5F22CW6973NQR15P8B9JWYH.

## Acceptance Criteria
- [x] `checkpoints(sessionId:)` returns the checkpoints of a key that was opened, snapshotted and released
- [x] `checkpoint(sessionId:index:)` works on a closed key
- [x] A key with no timeline gives `[]`, not an error

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SnapshotsGraphTests.swift`: against a real store in a temp dir, release the key, then query `checkpoints` and `checkpoint`
- [x] `swift test --filter Snapshots` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #graphql #snapshots