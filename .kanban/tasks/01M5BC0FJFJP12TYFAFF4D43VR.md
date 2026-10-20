---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5bce2schybqq76rgr32hdvp
  text: 'Precondition card on the FoundationModelsHooks board: 01M5BCDXCJ45S4B49QC031KJPH (031kjph), made by foundationmodelshooks-c3. That session runs /finish on it and sends the commit when it is on origin/main.'
  timestamp: 2026-10-20T00:47:27.532861+00:00
- actor: claude-code
  id: 01m5bcwrkmxvw8rgtf2z12azj2
  text: |-
    Research done.
    - The Hooks pin is updated. Package.resolved has FoundationModelsHooks 6380c1a. Package.resolved is in .gitignore, thus git shows no diff for it.
    - SnapshotStore.rollback(sessionKey:to:) validates the index first (before the pending take). Then it takes a pending snapshot, restores the full tree, and appends a checkpoint with the trigger rollback(to:). It returns nil when the work tree is already equal to the target tree. It sets the last tree to the restored tree.
    - The only verb alias mechanism in the code is UnknownToolHint.verbAliases (Discovery/UnknownToolHint.swift). Its documentation says: the alias only names the real path; it never calls it. A call of tools.snapshots.reset gives a repairable error that names tools.snapshots.rollback. Thus the acceptance item "reset and rewind call the rollback verb" does not agree with the mechanism that the card tells me to use. I use verbAliases, and I record this gap for a human decision.
    - The invalidCheckpoint corrective text comes from the SnapshotError extension in SnapshotsContext.swift. The error carries no count, thus the text tells the range in words (0 is the baseline, the highest index is the count of checkpoints).
  timestamp: 2026-10-20T00:55:28.628271+00:00
- actor: claude-code
  id: 01m5bd8pqkpmfw8syk8b865zz5
  text: |-
    Implementation landed (not committed).
    - Coordinator update applied: Package.resolved pins FoundationModelsHooks 0994b14 (after f35c5d0). The API is the same as 6380c1a.
    - A peer commit dcac6fb (InnerCallWitnessOpTests) needs a newer FoundationModelsExtras. The full build failed on it with the old local pin. I ran swift package update FoundationModelsExtras (now a63ddda). Package.resolved is gitignored, thus there is no diff.
    - The red step was a compile failure: RollbackSnapshot and RollbackSnapshotArguments did not exist, and the new trigger case made the SnapshotCheckpoint switch not exhaustive.
    - The text "undo that" stays in the rollback description, because the card tells the description to say it. The switch in SnapshotsContext still names the two "no checkpoint" cases of SnapshotError, with one generic text, because the compiler requires them.
    - The invalidCheckpoint text tells the range in words (0 is the baseline, the highest index is the count of checkpoints), because the error carries no count.
    - Open gap: the acceptance item "reset and rewind call the rollback verb" is not checked. The existing alias mechanism (UnknownToolHint.verbAliases) names the rollback path in a repairable error. It never calls it, by its documented design. A human must decide: accept the hint, or permit a new call mechanism.
  timestamp: 2026-10-20T01:01:59.923482+00:00
- actor: claude-code
  id: 01m5bd8t41pa0xgrafga2n8tta
  text: |-
    ### implement — stuck
    - evidence: 9 files. New: Sources/FoundationModelsMultitool/Capabilities/Snapshots/RollbackSnapshot.swift. Deleted: UndoSnapshot.swift, RedoSnapshot.swift. Changed: SnapshotsCapability.swift, SnapshotsContext.swift, SnapshotCheckpoint.swift, ListSnapshots.swift, Discovery/UnknownToolHint.swift, Package.swift (doc comment), Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift. swift test --filter SnapshotsCapabilityTests: 21 tests pass. Full swift test: 2511 tests in 220 suites pass, no compiler warnings.
    - next: a human decides the reset and rewind item (hint through verbAliases, or a real call). All other items are checked. Then /review.
  timestamp: 2026-10-20T01:02:03.393103+00:00
- actor: claude-code
  id: 01m5bdfmjvgvz74efdg4emr2yk
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (5b7cb69); 1 finding (1 confirmed, 1 refuted) — Sources/FoundationModelsMultitool/Capabilities/Snapshots/RollbackSnapshot.swift:94 duplication/duplication
    - next: implement the open item in the Review Findings section dated 2026-10-19 20:03; the task stays in review
  timestamp: 2026-10-20T01:05:47.099580+00:00
- actor: claude-code
  id: 01m5bdg3mw6fd8m88ztjfj1nzb
  text: |-
    ### finish iteration 1 — findings
    - implement: changed (after an alias decision) — 10 files; rollback added, undo and redo removed; Hooks pin 0994b14
    - test: green — swift test, 2511 tests in 220 suites passed, no warnings (from the implement run; no code change after it)
    - commit: 5b7cb69 (pushed to origin/main)
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Snapshots/RollbackSnapshot.swift:94
  timestamp: 2026-10-20T01:06:02.524097+00:00
- actor: claude-code
  id: 01m5bdr4t8t7jsv01qb0rj8t32
  text: |-
    Review finding (duplication, RollbackSnapshot corrective step) is done. Not committed.
    - New file Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsVerbResult.swift. Protocol SnapshotsVerbResult: requirements init() and a settable correction; one default corrective(_:). Sub-protocol SnapshotCheckpointResult: requirement init(checkpoint:isUnchanged:correction:) (the memberwise init satisfies it); one default result(of:).
    - ListSnapshotsResult, TakeSnapshotResult and RollbackSnapshotResult conform. To get init(), checkpoints has the default [] and isUnchanged has the default false. The Generable macro accepts these defaults, and the build has no warning. The schema that the model reads does not change.
    - The three private corrective(_:) steps are gone. The result(of:) steps of take and rollback were the same copy, thus they are gone too. ListSnapshots keeps its own result(of:), because its shape is different.
    - RED: the two new tests in SnapshotsCapabilityTests did not compile (no member corrective or result on the result types). GREEN: 23 tests in the suite pass.
    - Swift can share this code, thus no trade-off is recorded.
  timestamp: 2026-10-20T01:10:25.864698+00:00
- actor: claude-code
  id: 01m5bdr78s52d8hybama10w7zy
  text: |-
    ### implement — changed
    - evidence: 5 files. New: Sources/FoundationModelsMultitool/Capabilities/Snapshots/SnapshotsVerbResult.swift. Changed: ListSnapshots.swift, TakeSnapshot.swift, RollbackSnapshot.swift, Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift. swift test (one full run): 2513 tests in 220 suites pass, no compiler warning. The only build-system line is the known SwiftPM note "missing creator for mutated node" for the mlx-swift_Cmlx bundle, which is not from this change.
    - next: /review. The finding in Review Findings (2026-10-19 20:03) is checked.
  timestamp: 2026-10-20T01:10:28.377917+00:00
position_column: doing
position_ordinal: '80'
title: 'snapshots capability: replace undo and redo with rollback to a point in time'
---
## Context
The user asked for this on 2026-10-19: "we need a rollback 'to' a specific commit operation", "this is more than just an undo/redo, it'll go back to a point in time", "we really don't even need undo and redo -- just rollback to", and (relayed by testudoapp-4c) "it's git -- so a 'rollback to' is a revert, so it is append only". The user also agreed to the aliases `reset` and `rewind`, and requires no double checkpoint from a rollback. The TestudoApp spec matches this card: D95, MT-12 and HOOKS-3 in ../TestudoApp/features/packages/foundationmodels-multitool.md.

The `snapshots` capability (card 5wcd6b3, commits 0790531 and 9db1c0a) has `list`, `take`, `undo` and `redo`. After this card, it has `list`, `take` and `rollback` only. Use symbol names, not line numbers.

A rollback is NOT a series of undos. `SnapshotStore.reset(sessionKey:to:)` is a series of undos: it moves the later checkpoints to the redo stack, and the next change clears the redo stack. Do not use `reset`, `undo` or `redo` of the store.

A rollback is a revert to a point in time:
- It makes the full work tree equal to the tree of the selected point: the `after` tree of checkpoint N, or the baseline tree for index 0. It restores all files that are different, and it deletes files that did not exist at that point.
- The history is append only. The rollback itself becomes a new checkpoint at the end of the list, with the trigger `SnapshotTrigger.rollback(to:)`. The checkpoints after N stay in the list, thus the model can roll forward to any of them with a second rollback, also after a new change. To cancel a rollback, the model rolls back to the checkpoint before the rollback checkpoint.
- No double checkpoint: `SnapshotStore.rollback` sets the `last` tree of the store to the restored tree. Thus the `PostToolUse` snapshot of a `runCode` call that ran the rollback finds no change from the rollback. A change in the snippet before the rollback goes into the `pending` checkpoint. A change in the snippet after the rollback goes into the `PostToolUse` checkpoint. Both are correct.

## Precondition (other board)
The store at FoundationModelsHooks 2e29e38 cannot do this. A Hooks card (TestudoApp HOOKS-3) must add `SnapshotStore.rollback(sessionKey:to:)` and the trigger `SnapshotTrigger.rollback(to:)`, with the `last` tree rule above. The request went to the coordinating peer (foundationmodelsacpagent-a2). Until that is on Hooks origin/main, this card is blocked.
Met: Hooks origin/main 0994b14 has the API. The local Package.resolved pins 0994b14.

## What
- Update the local pin of FoundationModelsHooks to the commit with the new API.
- Remove the ops `undo snapshot` and `redo snapshot`: delete `UndoSnapshot.swift` and `RedoSnapshot.swift`, the shared `restore(_:)` helper in `SnapshotsContext`, `SnapshotRestoreResult`, and their tests. Remove them from `SnapshotsCapability`.
- Remove `isRedoAvailable` from `ListSnapshotsResult`, with `ListSnapshots.isRedoAvailable(in:sessionKey:)` and its tests. `list snapshots` does not read `undoneCheckpoints`.
- Remove each text that the model reads about undo, redo or a redo stack (op descriptions, corrective results, doc comments). If the compiler requires a case for `nothingToUndo` or `nothingToRedo` in a switch, give one generic text.
- Add the op `rollback snapshot` in `Sources/FoundationModelsMultitool/Capabilities/Snapshots/RollbackSnapshot.swift`, in the same shape as `TakeSnapshot`, and add it to `SnapshotsCapability`.
- The verb also accepts the names `reset` and `rewind`. Use the alias mechanism that other capabilities use for verbs; find it in the code. If no such mechanism exists, stop and report; do not invent one.
- Arguments (`@Generable`): `index: Int`, the checkpoint to go back to, as `list snapshots` shows it (from 1). Index 0 is the baseline (the state when the session opened).
- Result: the new rollback checkpoint and its changed files, or "no change". Use the `SnapshotsContext` helpers (`perform`, `resolve`).
- `SnapshotCheckpoint` shows the rollback trigger as text, for example "rollback to 2".
- Read the session key from `HookSession.current` at call time, as the other ops do.
- `SnapshotError.invalidCheckpoint` gives a corrective result that tells the valid range (0 to the checkpoint count) and tells the model to call `list snapshots`. Each other `SnapshotError` case gives its corrective result, as in the other ops.
- Update the doc comment about `runCode` to the rollback rules in Context.
- The capability and verb descriptions tell the model: call `list snapshots` first to find the index; "undo that" is a rollback to the checkpoint before the last one (index = count - 1); a rollback is itself a checkpoint, thus it can be rolled back too.

## Acceptance Criteria
- [x] The capability has the ops `list`, `take` and `rollback` only. No `undo` or `redo` op, type, helper or text is left in the Snapshots folder or in its tests.
- [x] `reset` and `rewind` go to the rollback verb through the existing alias mechanism, `UnknownToolHint.verbAliases`.
  - Decision (2026-10-19, orchestrator): the existing mechanism is the correct one. The TestudoApp spec (MT-12 item 5) asks for the aliases "if the alias mechanism of the capability supports it", and in this project an alias names the real path and does not call it. Thus a call of `tools.snapshots.reset` or `tools.snapshots.rewind` gives a repairable error that names `tools.snapshots.rollback` (tier `alias`). Do not add a new mechanism that calls the verb.
- [x] With three checkpoints, `rollback snapshot` with index 1 makes the full work tree equal to the tree after checkpoint 1, including deletion of a file that checkpoint 2 or 3 added.
- [x] After that rollback, `list snapshots` shows four checkpoints; the fourth has the trigger "rollback to 1".
- [x] After that rollback, `rollback snapshot` with index 3 gives the tree after checkpoint 3 again (roll forward).
- [x] After a rollback and a new file change, a rollback to a later point still works.
- [x] `rollback snapshot` with index 0 gives the baseline work tree.
- [x] An index below 0, or above the checkpoint count, gives the `invalidCheckpoint` corrective result, not an error, and the work tree does not change.
- [x] A rollback to a point equal to the work tree gives "no change" and makes no checkpoint.
- [x] A `runCode` snippet that only calls `tools.snapshots.rollback`, followed by the `PostToolUse` take of `SnapshotHook` (or a direct `store.take` with the `runCode` trigger), adds exactly one checkpoint, with the trigger `rollback(to:)`.
- [x] A snippet that changes a file, then rolls back, gives a `pending` checkpoint and then the rollback checkpoint, and no `PostToolUse` checkpoint.
- [x] A snippet that rolls back, then changes a file, gives the rollback checkpoint and then a `PostToolUse` checkpoint with only that file.
- [x] A call with no bound `HookSession.current` gives the `unavailable` corrective result.
- [x] One capability value, called under two bound `HookSession` values with different keys and work trees, rolls back the correct work tree for each key.
- [x] The discovery surface (`searchTools`) shows the three ops.

## Tests
- [x] Update `Tests/FoundationModelsMultitoolTests/SnapshotsCapabilityTests.swift` (Swift Testing) for each criterion above, with `TemporaryGitRepository` and `HookSession.$current.withValue`. No test may depend on timing.
- [x] Run `swift test` once in `/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool`. All tests pass.

## Workflow
- Use `/tdd`. Write the failing tests first, then implement. #hooks #snapshots

## Review Findings (2026-10-19 20:03)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 10 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/RedoSnapshot.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/UndoSnapshot.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/RedoSnapshot.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/UndoSnapshot.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/RedoSnapshot.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/UndoSnapshot.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/RedoSnapshot.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/UndoSnapshot.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/RedoSnapshot.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Sources/FoundationModelsMultitool/Capabilities/Snapshots/UndoSnapshot.swift, so its declarations are unread

- [x] `Sources/FoundationModelsMultitool/Capabilities/Snapshots/RollbackSnapshot.swift:94` `duplication/duplication` — The `corrective(_:)` step of RollbackSnapshot is a near-verbatim copy of the corrective step in TakeSnapshot and ListSnapshots. Each one wraps a message in its own result type with empty or nil fields. The copies can drift apart when the correction shape changes. Look for a shared way to build a correction-only result, such as one helper that takes the result type's initializer or a protocol with a default `corrective` implementation. If the three result types cannot share code in Swift, record the trade-off in the final report and keep the three one-line bodies, because each body is only a constructor call.
  - Resolution: the new file `Snapshots/SnapshotsVerbResult.swift` has the protocol `SnapshotsVerbResult` (requirements `init()` and a settable `correction`) with one default `corrective(_:)`. All three result types conform. The fields other than `correction` have empty default values. The sub-protocol `SnapshotCheckpointResult` has one default `result(of:)` for `take` and `rollback`, because that step was the same copy. The three private `corrective(_:)` steps and the two copies of `result(of:)` are gone from the Snapshots folder.
