---
assignees:
- claude-code
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