---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5bhavs8wa4k81673dme7ans
  text: |-
    Research done.
    - `swift package update FoundationModelsHooks` resolved main at 9a9e20a (Package.resolved revision 9a9e20a6234095ce5208153cbc96db83be4e45c8).
    - The verbs call only `checkpoints`, `take` and `rollback`. Of the new errors, only `timelineConflict` comes from these calls (a second store on the same store folder and key moves the ref first). `invalidSessionKey` and `sessionKeyOpen` come only from `open` and `remove`. `unreadableTimeline` comes only from `open`. A test can cause each of them through `SnapshotsContext.perform` with a store call, without timing.
    - `unreadableTimeline` without timing: the shadow repository has an alternates file that points to the objects of the source repository. Thus a test can write the SHA of a source commit that has a parent and no `Snapshot-Trigger` trailer into `<store folder>/<key>/refs/snapshots/timeline`, and then open the key again.
    - `changedWhileClosed` without timing: open, release, change the work tree, open a new store on the same folder. The open adds the checkpoint.
    - No Multitool test compares `Checkpoint.date` or depends on sub-second dates. The only date check is `!date.isEmpty` in the list test.
    - The text "undo that" in the rollback guidance of `RollbackSnapshot` is a user phrase, not a store API. The verb alias test for `snapshots.reset` names a guessed verb, not the store API. Both stay.
  timestamp: 2026-10-20T02:13:04.936818+00:00
- actor: claude-code
  id: 01m5bhfn33ajj7bt73cygc64dt
  text: |-
    Implementation landed (TDD).
    - RED: after the pin update, `swift build --build-tests` failed only on the production switches: "switch must be exhaustive" in `SnapshotCheckpoint.text(of:)`, and "no member nothingToUndo" in `SnapshotError.correctiveMessage`.
    - GREEN: `SnapshotCheckpoint.text(of:)` gives "changed while closed" for `changedWhileClosed`, and the trigger guide text names it. `SnapshotError.correctiveMessage` has no `nothingToUndo` or `nothingToRedo` case now, and has a text for `timelineConflict`, `unreadableTimeline`, `sessionKeyOpen` and `invalidSessionKey`. The shared sentence "Do not call tools.snapshots again in this session." is one private constant.
    - New tests in SnapshotsCapabilityTests: list shows a changedWhileClosed checkpoint (release, change, open a second store on the same folder); take after a second store moved the ref gives timelineConflict; open over a timeline ref that names a source commit with no trigger trailer gives unreadableTimeline; remove of the open key gives sessionKeyOpen; a key with a slash gives invalidSessionKey; and each new correction names tools.snapshots. No test reads a clock or waits.
    - `swift test`: 2519 tests in 220 suites passed, 0 failures. The one "warning:" line in the log is the SwiftPM build-system line "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It was also in the RED build before any source change, and it is not a compiler warning of Multitool.
    - Package.resolved is in .gitignore, thus the pin update is local only.
  timestamp: 2026-10-20T02:15:41.923157+00:00
- actor: claude-code
  id: 01m5bhfqb3ek573p74396vkbxj
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotCheckpoint.swift, Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsContext.swift, Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift; swift test 2519 tests in 220 suites passed; Package.resolved (gitignored) at 9a9e20a
    - next: review
  timestamp: 2026-10-20T02:15:44.227395+00:00
- actor: claude-code
  id: 01m5bhk27cf9t3e6gfqh8rr7se
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit dafebbb). 0 findings, 0 confirmed, 1 refuted. 3 files reviewed. 2 files in .kanban are not reviewed because of an ignore rule. The task has no prior review findings.
    - next: none. The task moved to done.
  timestamp: 2026-10-20T02:17:33.676002+00:00
- actor: claude-code
  id: 01m5bhkccn65cpfd5epzvstqy3
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files; Hooks pin 9a9e20a
    - test: green — swift test, 2519 tests in 220 suites passed, 0 failures (from the implement run; no code change after it)
    - commit: dafebbb (pushed to origin/main)
    - review: clean — 0 findings; task is in done
  timestamp: 2026-10-20T02:17:44.085626+00:00
position_column: done
position_ordinal: ffffffa980
title: 'snapshots capability: adapt to FoundationModelsHooks 9a9e20a'
---
## Context
foundationmodelshooks-c3 reported on 2026-10-19 that FoundationModelsHooks origin/main is 9a9e20a, with these changes:
- Removed from `SnapshotStore`: `undo`, `redo`, `reset(sessionKey:to:)`, `undoneCheckpoints`, and the errors `nothingToUndo` and `nothingToRedo` (c3a13eb).
- New trigger case `SnapshotTrigger.changedWhileClosed`: a snapshot on open when the work tree changed while the app was closed.
- New errors: `timelineConflict`, `sessionKeyOpen`, `unreadableTimeline`, `invalidSessionKey`.
- `Checkpoint.date` is now in whole seconds. `rollback(sessionKey:to:)` is unchanged, and the timeline now survives a restart.

CI builds Multitool against the main heads of the sibling packages. Thus the Multitool main does not compile with this Hooks main: the switches on `SnapshotError` and `SnapshotTrigger` in the Snapshots folder name removed cases and do not cover the new cases. Use symbol names, not line numbers.

## What
- Update the local pin of FoundationModelsHooks to 9a9e20a or later (`swift package update FoundationModelsHooks`).
- `SnapshotsContext`: remove the generic text for `nothingToUndo` and `nothingToRedo`. Add a corrective text for each new `SnapshotError` case that tells the model why the call failed and what to do, in the style of the other cases. Read the doc comment of each case in ../FoundationModelsHooks first.
- `SnapshotCheckpoint`: show `changedWhileClosed` as text that the model understands, for example "changed while closed".
- Remove each other reference in Multitool (sources, tests, doc comments) to an API that Hooks removed.
- Check each test that compares `Checkpoint.date` or depends on sub-second dates.

## Acceptance Criteria
- [x] Multitool compiles with FoundationModelsHooks 9a9e20a, with no warnings.
- [x] No reference to `undo`, `redo`, `reset`, `undoneCheckpoints`, `nothingToUndo` or `nothingToRedo` of the store is left in Multitool.
- [x] Each new `SnapshotError` case gives a corrective result, not a thrown error. A test covers each case that a test can cause without timing.
- [x] `list snapshots` shows a `changedWhileClosed` checkpoint with its text. Add a test if the store lets a test make one (for example by closing and opening the store over a changed work tree); else record why not.

## Tests
- [x] Update `Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift` (Swift Testing). No test may depend on timing.
- [x] Run `swift test` once in `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool`. All tests pass.

## Workflow
- Use `/tdd`. Write the failing tests first, then implement. #hooks #snapshots