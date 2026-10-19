---
comments:
- actor: claude-code
  id: 01m5aypa29neay1far20ft9nsa
  text: |-
    Research done.
    - FoundationModelsHooks origin/main is 07b70ca. Public API: SnapshotStore(directory:), open(sessionKey:owner:workingDirectory:), release, take(sessionKey:trigger:) -> Checkpoint?, checkpoints(sessionKey:), undo(sessionKey:) -> Checkpoint, redo(sessionKey:) -> Checkpoint, reset(sessionKey:to:). Checkpoint has index, trigger, before, after, files, date. HookSession.current is a TaskLocal.
    - GAP: the store has no public read of the redo stack. The card asks list snapshots to "also say if a redo is available". The capability cannot know this without a new store API (for example a read of the undone checkpoints). This needs a change in FoundationModelsHooks.
    - JSCInterpreter runs each job on a private DispatchQueue. The job queue has no task-local value (see RunTelemetry in JSCInterpreter.swift). Thus HookSession.current does not reach an inner tools.snapshots call in a runCode snippet unless the run binds it again around each job, as it does for the logger. The Extras background lane uses Task {} (not detached), which copies task locals.
    - Pattern: GitCapability + Status.swift; in-band corrections through CorrectiveFailure and Result.resolve(corrective:then:) in Capabilities/Files/CorrectiveResult.swift. Discovery test helper: CapabilityDiscoveryProbe.searchToolsFeedback.
  timestamp: 2026-10-19T20:47:17.065700+00:00
- actor: claude-code
  id: 01m5az9xqsjh0cersg146ydwgf
  text: |-
    Implementation landed (not committed).
    - Package.swift: FoundationModelsHooks through swissArmyHammerPackage(name:), product linked to the library target and the unit test target. Resolved at 07b70ca.
    - New folder Sources/FoundationModelsMultitool/Capabilities/Snapshots: SnapshotsCapability.swift, SnapshotsContext.swift (reads HookSession.current?.sessionKey at call time; SnapshotError conforms to CorrectiveFailure), SnapshotCheckpoint.swift (the checkpoint value and the shared undo and redo result), ListSnapshots.swift, TakeSnapshot.swift, UndoSnapshot.swift, RedoSnapshot.swift.
    - JSCInterpreter.swift: the Run reads HookSession.current in the calling task and binds it again around each job, the same as the logger. Without this, a tools.snapshots call in a runCode snippet saw no session (the new snippet test failed first, then passed).
    - Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift: 11 tests.
    - Local pin note: the local Package.resolved (gitignored) held FoundationModelsExtras 1f586a7, which does not have BackgroundWork, thus main did not build locally. I moved the local pins of Extras, Router and CodeContext to the branch heads (the CI state). No tracked file changed for this.
    - Full run: swift test, 2500 tests in 219 suites passed.
  timestamp: 2026-10-19T20:57:59.801529+00:00
- actor: claude-code
  id: 01m5aza4kp564v2b3hpsp24j20
  text: |-
    BLOCKER: one requirement is not done. The card says list snapshots must "also say if a redo is available". SnapshotStore at 07b70ca has no public read of its redo stack (SnapshotHistory.undone is private; the public API is open, release, take, checkpoints, undo, redo, reset). The capability cannot know if a redo is available without a store change: a trial redo changes the work tree, and a count kept in the capability goes wrong when the hook or another fork takes a snapshot. Proposed fix in FoundationModelsHooks: add a public read, for example `public func undoneCheckpoints(sessionKey: String) async throws -> [Checkpoint]` (or a Bool `canRedo(sessionKey:)`), on the board of that repository. After it lands, add an isRedoAvailable field to ListSnapshotsResult and a test for it.
    Also note: undo and redo share one result type, SnapshotRestoreResult, in SnapshotCheckpoint.swift, because the two results are the same; each op file holds its own arguments.

    ### implement — stuck
    - evidence: swift test, 2500 tests in 219 suites passed; 11 new tests in SnapshotsCapabilityTests. Files: Package.swift, JSCInterpreter.swift, Capabilities/Snapshots (7 files), SnapshotsCapabilityTests.swift.
    - next: a FoundationModelsHooks change to expose the redo stack, then add the redo-available field to list snapshots.
  timestamp: 2026-10-19T20:58:06.838627+00:00
- actor: claude-code
  id: 01m5azaxwj22h2jzp8dcrzcbgq
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 10 files changed; swift test, 2500 tests in 219 suites passed (11 new in SnapshotsCapabilityTests)
    - test: not run (implement was stuck)
    - commit: none (work is in the working tree, not committed)
    - review: not run
    - blocker: list snapshots must say if a redo is available. SnapshotStore at Hooks 07b70ca has no public read of the redo stack. A Hooks change is necessary, for example `canRedo(sessionKey:)` or `undoneCheckpoints(sessionKey:)`. Request sent to foundationmodelsacpagent-a2.
  timestamp: 2026-10-19T20:58:32.722840+00:00
- actor: claude-code
  id: 01m5b012mnzkfj5bzbvzr9ps14
  text: |-
    The blocker is resolved. FoundationModelsHooks origin/main 2e29e38 adds SnapshotStore.undoneCheckpoints(sessionKey:). The local pin moved to 2e29e38 (swift package update FoundationModelsHooks).
    - ListSnapshotsResult has the new field isRedoAvailable. The list reads the checkpoints, then the redo stack. When the second read throws SnapshotError.unavailable (the key closed between the two reads), the list stays valid and isRedoAvailable is false. Each other error of the store becomes the correction, as before. A corrective list has isRedoAvailable false.
    - TDD: two new tests failed first (no member isRedoAvailable), then passed. Test 1: a redo is not available before an undo, is available after an undo, and is not available after the redo. Test 2: a list with no bound session gives the unavailable correction and no redo.
    - No test forces the close between the two reads, because the store has no seam for it and a test must not depend on timing. The catch of SnapshotError.unavailable in ListSnapshots.isRedoAvailable(in:sessionKey:) is the code for that case.
    - The card has no open requirement now.

    ### implement — changed
    - evidence: swift test, 2502 tests in 219 suites passed, no warnings in project files; 13 tests in SnapshotsCapabilityTests. Files: Package.swift, Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift, Sources/FoundationModelsMultitool/Capabilities/Snapshots (SnapshotsCapability.swift, SnapshotsContext.swift, SnapshotCheckpoint.swift, ListSnapshots.swift, TakeSnapshot.swift, UndoSnapshot.swift, RedoSnapshot.swift), Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift.
    - next: review.
  timestamp: 2026-10-19T21:10:38.485473+00:00
position_column: doing
position_ordinal: '80'
title: 'snapshots capability: list, take, undo and redo over a shared SnapshotStore'
---
## Context
This card is a Multitool change for the hook system that was designed in a FoundationModelsACPAgent session (2026-10-19). The user approved this change on 2026-10-19.

Precondition (other board): the FoundationModelsHooks cards 01M5ARTC56ZSHRXFYA7P8X3NXB (`HookSession.current`) and 01M5ARTJJ62RQX50B47G76HHYR (`SnapshotStore`) are done, and `swissarmyhammer/FoundationModelsHooks` is on GitHub. Until then, this card is blocked.

## What
Add a `snapshots` capability that lets the model list and act on the workspace snapshots of its session. It uses a `SnapshotStore` that the host gives to it. The same store also goes to `SnapshotHook`, which takes the snapshots automatically on the tool events. The capability does not know about hooks. Use symbol names, not line numbers.

- `Package.swift`: add `FoundationModelsHooks` with `swissArmyHammerPackage(name:)`, and link its product to the library target. It uses the same `swift-libgit2` version (1.9.7), so SwiftPM resolves one copy.
- `Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsCapability.swift`: `public struct SnapshotsCapability: Capability`, `noun = "snapshots"`, `public init(store: SnapshotStore)`. Follow the shape of `GitCapability` (`Capabilities/Git/GitCapability.swift`).
- **Session key at call time.** The capability does NOT get a session key when it is built: the registry is built before the session exists, and `MultiTool.forked()` returns the same tool for a fork. Each op reads `HookSession.current?.sessionKey` at call time; Router binds `HookSession.current` for each model call. Thus a fork in a different working directory uses its own key. If Multitool runs a verb in a detached task (for example the background lane of `runCode`), carry `HookSession.current` into that task. When `HookSession.current` is `nil`, each op gives the `unavailable` corrective result.
- One file for each op, with `@Generable` arguments and results, as `Capabilities/Git/Status.swift` does:
  - `list snapshots`: each checkpoint: index, trigger (tool name and tool call ID, the label, or "pending"), changed files, date. Also say if a redo is available.
  - `take snapshot`: optional `label`. Gives the new checkpoint, or "no change".
  - `undo snapshot`: undoes the last checkpoint, and gives the restored files.
  - `redo snapshot`: redoes the last undo, and gives the files.
- Each `SnapshotError` case of the store (`unavailable`, `nothingToUndo`, `nothingToRedo`, `invalidCheckpoint`, `workingDirectoryMismatch`) gives a corrective result that says why, in the style of the other capabilities. It does not throw out of the tool.
- Doc comment: an undo inside a `runCode` snippet sets the store's `last` to the restored tree, so the `PostToolUse` snapshot of that `runCode` call finds no change and makes no checkpoint. An undo can also run before the snapshot of the tool call before it; the store then records that change as `.pending`.

## Acceptance Criteria
- [ ] `list snapshots` over a store with two checkpoints gives both, oldest first.
- [ ] `take snapshot` with a label after a file write gives a checkpoint with that label.
- [ ] `undo snapshot` then `redo snapshot` gives the work tree before the undo.
- [ ] `undo snapshot` with nothing to undo and `redo snapshot` with nothing to redo give the corrective results, not errors.
- [ ] A call with no bound `HookSession.current`, or for a key whose session is not in a git work tree, gives the `unavailable` corrective result.
- [ ] One capability value, called under two bound `HookSession` values with different keys and work trees, acts on the correct store state for each key.
- [ ] The capability is in the discovery surface (`searchTools`) with its four ops.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift` (Swift Testing): each criterion above, with `TemporaryGitRepository` from the test support target, and `HookSession.$current.withValue` to bind the session.
- [ ] Run `swift test` in `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool`. All tests pass.

## Workflow
- Use `/tdd`. Write the failing tests first, then implement.

#hooks #snapshots