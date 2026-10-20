// `RollbackSnapshot` — the `tools.snapshots.rollback` verb.
//
// The verb makes the full work tree of the session key of the bound session
// equal to the tree after one checkpoint, or to the baseline for index 0. A
// rollback is a revert, as in git: the history is append only. The rollback
// itself becomes a new checkpoint at the end of the list, and the checkpoints
// after the restored one stay. Thus a second rollback can roll forward, and a
// rollback can itself be rolled back.
//
// A rollback inside a `runCode` snippet does not make a second checkpoint.
// The store sets its `last` tree to the restored tree. A change in the
// snippet before the rollback goes into a `pending` checkpoint. The
// `PostToolUse` snapshot of the `runCode` call finds only the changes after
// the rollback, and makes no checkpoint when there is none.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// snapshots capability, in the pattern of `Capabilities/Git/Status.swift`.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The arguments of `tools.snapshots.rollback`: the checkpoint to go back to.
@Generable
struct RollbackSnapshotArguments {

    /// The index of the checkpoint to go back to, as `tools.snapshots.list`
    /// gives it. The index 0 is the baseline.
    @Guide(
        description:
            "The index of the checkpoint to go back to, as tools.snapshots.list gives it (from 1). 0 is the "
            + "baseline: the state when the session opened.")
    var index: Int
}

/// The result of `tools.snapshots.rollback`: the new rollback checkpoint,
/// "no change", or the correction that says why no rollback was made.
@Generable(
    description: "the new rollback checkpoint with the files it changed, or isUnchanged when the work tree is "
        + "already equal to that point, or the correction that says why no rollback was made.")
struct RollbackSnapshotResult: SnapshotCheckpointResult {

    /// The new rollback checkpoint, or `nil` when no checkpoint was made.
    @Guide(
        description:
            "The new rollback checkpoint. Its files are the files that the rollback restored or deleted. null "
            + "when no checkpoint was made.")
    var checkpoint: SnapshotCheckpoint?

    /// Whether the work tree was already equal to the selected point.
    @Guide(
        description: "True when the work tree is already equal to that point, thus no checkpoint was made.")
    var isUnchanged = false

    /// Why no rollback was made, or `nil` when the rollback ran.
    @Guide(description: "Why no rollback was made; null when the rollback ran.")
    var correction: String?
}

extension RollbackSnapshot {

    // MARK: Execution

    /// Makes the work tree of the session key of the bound session equal to
    /// the tree after checkpoint `arguments.index`.
    ///
    /// - Parameter arguments: The index of the checkpoint.
    /// - Returns: The new rollback checkpoint, "no change", or the
    ///   correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: RollbackSnapshotArguments) async throws -> RollbackSnapshotResult {
        let index = arguments.index
        return try await context.perform { store, sessionKey in
            try await store.rollback(sessionKey: sessionKey, to: index)
        }.resolve(corrective: RollbackSnapshotResult.corrective, then: RollbackSnapshotResult.result(of:))
    }
}

/// Makes the work tree equal to an earlier point, and records that as a new
/// checkpoint.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { checkpoints } = await tools.snapshots.list({});
/// //   await tools.snapshots.rollback({ index: checkpoints.length - 1 });
/// ```
struct RollbackSnapshot: Tool {

    /// The verb this tool renders as, which the snapshots noun stands in
    /// front of: `tools.snapshots.rollback`.
    let name = "rollback"

    /// The usage instructions, as the model reads them.
    let description = """
        rollback makes the whole work tree equal to the point after one checkpoint: it restores each changed \
        file and deletes each file that did not exist at that point. Call tools.snapshots.list first to find \
        the index. index 0 is the baseline (the state when the session opened). To take back the last change \
        ("undo that"), roll back to index = count - 1, where count is the number of checkpoints. The rollback \
        is itself a new checkpoint at the end of the list, and the later checkpoints stay, thus you can roll \
        forward to them or roll back the rollback. When the work tree is already equal to that point, no \
        checkpoint is made and isUnchanged is true. An index that is not valid comes back as a correction \
        rather than as an error — read it and act on it.
        """

    /// The session context this verb writes against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
