// `RedoSnapshot` — the `tools.snapshots.redo` verb.
//
// The verb redoes the last undo of the session key of the bound session: the
// store restores the files of the undone checkpoint to their state after it,
// and moves the checkpoint back to the checkpoint list. A change of the work
// tree after the undo clears the redo list, thus such a redo comes back as
// the correction of `SnapshotError.nothingToRedo`.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// snapshots capability, in the pattern of `Capabilities/Git/Status.swift`.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The arguments of `tools.snapshots.redo`: none.
@Generable
struct RedoSnapshotArguments {}

extension RedoSnapshot {

    // MARK: Execution

    /// Redoes the last undo of the session key of the bound session.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The redone checkpoint, whose files are the restored files,
    ///   or the correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: RedoSnapshotArguments) async throws -> SnapshotRestoreResult {
        try await context.perform { store, sessionKey in
            try await store.redo(sessionKey: sessionKey)
        }.resolve(corrective: SnapshotRestoreResult.corrective, then: SnapshotRestoreResult.restored)
    }
}

/// Redoes the last undo and restores its files.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { checkpoint } = await tools.snapshots.redo({});
/// ```
struct RedoSnapshot: Tool {

    /// The verb this tool renders as, which the snapshots noun stands in
    /// front of: `tools.snapshots.redo`.
    let name = "redo"

    /// The usage instructions, as the model reads them.
    let description = """
        redo puts back the change of the last tools.snapshots.undo, and gives the redone checkpoint; its \
        files are the restored files. A change of the work tree after the undo clears the redo list. Nothing \
        to redo comes back as a correction rather than as an error — read it and act on it.
        """

    /// The session context this verb writes against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
