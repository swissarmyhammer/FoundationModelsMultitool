---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5d952k8kdrk5me7vaxw617a
  text: |-
    Agreed API with foundationmodelshooks-8b (HOOKS-5, Hooks cards ^rnqwhs1 and ^x3r4ntw), 2026-10-20. Names can change before the Hooks push:
    - The old calls are removed. The new calls are `take(sessionKey:owner:trigger:)`, `checkpoints(sessionKey:owner:)` and `rollback(sessionKey:owner:to:)`.
    - New `SnapshotError` cases: `indirect case notAvailable(cause: SnapshotError)`, `case repositoryFailure(description: String)` (only as a cause), and `case noTimeline` (only from `timelineSummary`).
    - `unavailable` now also means "this owner did not open the key". Change its text, which today says only "not in a git work tree".
    - The `take` or `rollback` that meets the conflict throws `.timelineConflict` itself. The later calls throw `.notAvailable(cause: .timelineConflict)`.
    - The text names only the cause case, and never the `description` of `repositoryFailure`, because it can hold a path.
    - Give `noTimeline` a text in the exhaustive `switch`, although Multitool does not call `timelineSummary`.
    - Multitool main does not build from the Hooks push until this card is pushed. Do this card at once when Hooks sends the sha.
  timestamp: 2026-10-20T18:28:35.560435+00:00
- actor: claude-code
  id: 01m5d95dkcnntg2144rgnem8sy
  text: 'Change to the agreed API (2026-10-20, with foundationmodelsacpagent-68 and foundationmodelshooks-8b): the cause is a small enum, not an indirect SnapshotError. `case notAvailable(cause: SnapshotUnavailableCause)` with the cases `workingDirectoryMismatch`, `timelineConflict` and `openFailed`. A failed open with an error that is not a SnapshotError gives `openFailed`. The text must name each of the three cases. `repositoryFailure(description:)` may not exist. Use the names that Hooks pushes.'
  timestamp: 2026-10-20T18:28:46.828011+00:00
position_column: todo
position_ordinal: '80'
title: 'Snapshots: say "not available for this session" after a timeline error (ACPA-15)'
---
FoundationModelsACPAgent asks for this change for ACPA-15 (its card ^j4pd8zw).

BLOCKED: this needs FoundationModelsHooks card ^x3r4ntw on Hooks origin/main. On 2026-10-20, Hooks origin/main is 9a9e20a, and that card is not done. Check Hooks origin/main yourself before you start.

The problem: after a timeline error (`workingDirectoryMismatch` for a moved project, or `timelineConflict`), `tools.snapshots.list` gives the `unavailable` text ("not in a git work tree"). That reason is wrong. In one case, it also gives the checkpoints of another session that has the same key open.

The Hooks part (^x3r4ntw): `SnapshotStore` records a failed `open` or a `timelineConflict` for each `(sessionKey, owner)`. `checkpoints`, `take` and `rollback` take the calling `owner`. For a session with a recorded error, they throw a new case, for example `SnapshotError.notAvailable(cause:)`. Use the names that Hooks pushes.

The Multitool part:
1. `SnapshotsContext.perform` (`Capabilities/Snapshots/SnapshotsContext.swift`) reads `HookSession.current?.sessionID` and passes it as the `owner` to `checkpoints`, `take` and `rollback` (`ListSnapshots.swift`, `RollbackSnapshot.swift`, and the verb that takes a snapshot).
2. `SnapshotError.correctiveMessage` for the new case says: "Snapshots are not available for this session: <case>. Do not call tools.snapshots again in this session." Here <case> is `workingDirectoryMismatch` or `timelineConflict`. Give no path and no file content.
3. A test of each case with a temporary store: a moved working directory, and a timeline conflict. Each test checks the text, and checks that `list` does not give the checkpoints of the other owner.

After the push, send the sha to foundationmodelsacpagent-68. #blocked-external