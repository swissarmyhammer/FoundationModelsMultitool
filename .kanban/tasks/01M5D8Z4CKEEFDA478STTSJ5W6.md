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
- actor: claude-code
  id: 01m5d9qyx3q00ekq08mnrwmj72
  text: |-
    ### finish iteration 1 — stuck
    - implement: not started. Blocked by FoundationModelsHooks ^x3r4ntw.
    - evidence: `git fetch origin` in ../FoundationModelsHooks on 2026-10-20 gives origin/main 9a9e20a. `git grep` finds no `SnapshotUnavailableCause` and no `owner:` on `take`, `checkpoints` or `rollback`.
    - next: when foundationmodelshooks-8b sends the HOOKS-5 sha, run /finish ^ttsj5w6.
  timestamp: 2026-10-20T18:38:54.371609+00:00
- actor: claude-code
  id: 01m5da7waw4a6p928qmx1trjs8
  text: |-
    Research (2026-10-20). Hooks checkout is at c66f336 after `swift package update FoundationModelsHooks`.
    - Hooks API: `take(sessionKey:owner:trigger:)`, `checkpoints(sessionKey:owner:)`, `rollback(sessionKey:owner:to:)`. `SnapshotError.notAvailable(cause: SnapshotUnavailableCause)` with the String raw-value cases `workingDirectoryMismatch`, `timelineConflict`, `openFailed`. `SnapshotError.noTimeline` comes only from `timelineSummary`. No `repositoryFailure` case exists.
    - `SnapshotUnavailableCause(of:)` maps each open error that is not `workingDirectoryMismatch` or `timelineConflict` to `openFailed`. Thus an open over a timeline commit with no trigger (`unreadableTimeline`) records `openFailed`. The tests use that to produce `openFailed` through the store.
    - A second open of a key that is open with a different working directory throws `workingDirectoryMismatch` from the in-memory check, and records the cause for that owner only.
    - After a conflict, the key state has `failure = .timelineConflict`, thus each owner of the key on that store gets `notAvailable(cause: .timelineConflict)`.
    - Plan: `SnapshotsContext.perform` gives the operation `(store, sessionKey, owner)`, where `owner` is `HookSession.current.sessionID`.
  timestamp: 2026-10-20T18:47:36.028029+00:00
- actor: claude-code
  id: 01m5daggrnq9phhv92c66p09n2
  text: |-
    Implementation landed (not committed, not pushed).
    - `SnapshotsContext.perform` gives the operation `(store, sessionKey, owner)`. The owner is `HookSession.current.sessionID`. With no bound session, the result is the `unavailable` correction.
    - `list`, `take` and `rollback` give the owner to `checkpoints(sessionKey:owner:)`, `take(sessionKey:owner:trigger:)` and `rollback(sessionKey:owner:to:)`.
    - New texts: `notAvailable(cause:)` gives "Snapshots are not available for this session: <cause.rawValue>. Do not call tools.snapshots again in this session." `noTimeline` has its own text. The `unavailable` text now also says "this session did not open its session key".
    - Tests through the store: moved project (a copy of the work tree in a new folder) gives `workingDirectoryMismatch`; a take after a second store moved the timeline, then `list`, gives `timelineConflict`; an open over a timeline commit with no trigger (from a second store, while the first store has the key open) gives `openFailed`. Each test checks the text and that `list` gives no checkpoint of the other owner. A further test: a session that did not open the key gets `unavailable` and no checkpoint of the open session.
    - The card says: after the push, send the sha to foundationmodelsacpagent-68. The commit step must do that.
    - `swift test` output has one SwiftPM build-system line: "warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS". It comes from the mlx-swift dependency build, not from a compiler diagnostic of this change.
  timestamp: 2026-10-20T18:52:19.093918+00:00
- actor: claude-code
  id: 01m5dagkef1cz4wgrsdtdbvse0
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/Snapshots/{SnapshotsContext.swift, ListSnapshots.swift, TakeSnapshot.swift, RollbackSnapshot.swift, SnapshotsCapability.swift}, Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift. `swift test` (one run, Hooks c66f336): 2528 tests in 220 suites passed, 0 failures.
    - next: /review ^ttsj5w6, then commit and push, then send the sha to foundationmodelsacpagent-68.
  timestamp: 2026-10-20T18:52:21.839747+00:00
- actor: claude-code
  id: 01m5damexnsychhq1m1xptfqr1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 66268e4). 6 files reviewed. Counts: findings 0, confirmed 0, refuted 1, attempted 7, failed 0, skipped 0. The engine did not review 2 .kanban files (.reviewignore).
    - next: The task is in done. Send the sha to foundationmodelsacpagent-68 after the push.
  timestamp: 2026-10-20T18:54:28.277260+00:00
- actor: claude-code
  id: 01m5damxhymmrhtt8pt0s8d2ve
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 6 files (SnapshotsContext, ListSnapshots, TakeSnapshot, RollbackSnapshot, SnapshotsCapability, SnapshotsCapabilityTests)
    - test: green — swift test, 2528 tests in 220 suites passed, against Hooks c66f336
    - commit: 66268e4
    - review: clean — review sha HEAD~1..HEAD, findings 0, refuted 1
    - next: the user approves the push; then send the sha to testudoapp-4c, foundationmodelsacpagent-68 and foundationmodelshooks-8b.
  timestamp: 2026-10-20T18:54:43.262880+00:00
position_column: done
position_ordinal: ffffffab80
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

After the push, send the sha to foundationmodelsacpagent-68.