// `UndoSnapshot` — the `tools.snapshots.undo` verb.
//
// The verb undoes the last checkpoint of the session key of the bound
// session: the store first records each change that no snapshot recorded (a
// `pending` checkpoint), then restores the files of the last checkpoint to
// their state before it, and moves the checkpoint to the redo list.
//
// An undo inside a `runCode` snippet sets the `last` tree of the store to the
// restored tree. Thus the `PostToolUse` snapshot of that `runCode` call finds
// no change and makes no checkpoint. An undo can also run before the snapshot
// of the tool call before it; the store then records that change as
// `pending`, and the late snapshot of that tool call finds no change.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// snapshots capability, in the pattern of `Capabilities/Git/Status.swift`.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The arguments of `tools.snapshots.undo`: none.
@Generable
struct UndoSnapshotArguments {}

extension UndoSnapshot {

    // MARK: Execution

    /// Undoes the last checkpoint of the session key of the bound session.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The undone checkpoint, whose files are the restored files,
    ///   or the correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: UndoSnapshotArguments) async throws -> SnapshotRestoreResult {
        try await context.perform { store, sessionKey in
            try await store.undo(sessionKey: sessionKey)
        }.resolve(corrective: SnapshotRestoreResult.corrective, then: SnapshotRestoreResult.restored)
    }
}

/// Undoes the last checkpoint and restores its files.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { checkpoint } = await tools.snapshots.undo({});
/// ```
///
/// An undo inside a `runCode` snippet sets the `last` tree of the store to the
/// restored tree, thus the `PostToolUse` snapshot of that `runCode` call finds
/// no change and makes no checkpoint. An undo that runs before the snapshot of
/// the tool call before it makes the store record that change as `pending`.
struct UndoSnapshot: Tool {

    /// The verb this tool renders as, which the snapshots noun stands in
    /// front of: `tools.snapshots.undo`.
    let name = "undo"

    /// The usage instructions, as the model reads them.
    let description = """
        undo restores the files of the last checkpoint to their state before that checkpoint, and gives the \
        undone checkpoint; its files are the restored files. A change that no snapshot recorded yet is \
        recorded first as a pending checkpoint, thus undo restores the state before the last change. Call \
        tools.snapshots.redo to put the undone change back. Nothing to undo comes back as a correction rather \
        than as an error — read it and act on it.
        """

    /// The session context this verb writes against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
