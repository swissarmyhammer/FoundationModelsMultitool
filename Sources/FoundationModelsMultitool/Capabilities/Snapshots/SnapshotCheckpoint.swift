// `SnapshotCheckpoint` — one checkpoint of the store, as each verb of the
// snapshots capability writes it, and `SnapshotRestoreResult`, the result of
// the `undo` and `redo` verbs.
//
// A `Checkpoint` of FoundationModelsHooks carries two tree IDs that the model
// cannot use. This value carries what the model reads: the index, the
// trigger as text, the changed files, and the date in ISO 8601 (UTC), the
// same form as the dates of the git verbs.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// One checkpoint: a recorded change of the work tree.
@Generable(description: "one checkpoint: a recorded change of the work tree.")
struct SnapshotCheckpoint: Equatable {

    /// The position of the checkpoint, from 1 for the oldest checkpoint.
    @Guide(description: "The position of the checkpoint, from 1 for the oldest checkpoint.")
    var index: Int

    /// The event that took the snapshot, as text.
    @Guide(
        description:
            "What took the snapshot: 'tool <name> (call <id>)' for a tool call, 'label <text>' or 'manual' for "
            + "tools.snapshots.take, or 'pending' for a change that an undo or a redo recorded first.")
    var trigger: String

    /// The files that the checkpoint changed.
    @Guide(description: "The files that the checkpoint changed, relative to the work tree.")
    var files: [String]

    /// The time of the snapshot.
    @Guide(description: "The time of the snapshot, ISO 8601 in UTC.")
    var date: String
}

extension SnapshotCheckpoint {

    /// The form of each date that a result writes: ISO 8601 in UTC.
    private static let dateStyle = Date.ISO8601FormatStyle(timeZone: .gmt)

    /// Makes the value that the model reads from a checkpoint of the store.
    ///
    /// - Parameter checkpoint: The checkpoint of the store.
    init(_ checkpoint: Checkpoint) {
        self.init(
            index: checkpoint.index, trigger: Self.text(of: checkpoint.trigger), files: checkpoint.files,
            date: Self.dateStyle.format(checkpoint.date))
    }

    /// The text of a trigger, as the model reads it.
    ///
    /// - Parameter trigger: The event that took the snapshot.
    /// - Returns: The text.
    static func text(of trigger: SnapshotTrigger) -> String {
        switch trigger {
        case .toolUse(let toolCallID, let toolName):
            "tool \(toolName) (call \(toolCallID))"
        case .manual(let label?):
            "label \(label)"
        case .manual(nil):
            "manual"
        case .pending:
            "pending"
        }
    }
}

/// The result of `tools.snapshots.undo` and `tools.snapshots.redo`: the
/// checkpoint that the verb moved, or the correction that says why no
/// checkpoint moved.
///
/// `correction` and `checkpoint` are exclusive.
@Generable(
    description: "the checkpoint that the undo or the redo moved, with the files it restored, or the correction "
        + "that says why no checkpoint moved.")
struct SnapshotRestoreResult {

    /// The moved checkpoint. Its files are the restored files.
    @Guide(
        description:
            "The checkpoint that the undo or the redo moved. Its files are the files that were restored. null "
            + "when no checkpoint moved.")
    var checkpoint: SnapshotCheckpoint?

    /// Why no checkpoint moved, or `nil` when one moved.
    @Guide(description: "Why no checkpoint moved; null when one moved.")
    var correction: String?
}

extension SnapshotRestoreResult {

    /// The result of a checkpoint that moved.
    ///
    /// - Parameter checkpoint: The moved checkpoint of the store.
    /// - Returns: The result.
    static func restored(_ checkpoint: Checkpoint) -> SnapshotRestoreResult {
        SnapshotRestoreResult(checkpoint: SnapshotCheckpoint(checkpoint), correction: nil)
    }

    /// A result that carries only a correction.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective result.
    static func corrective(_ message: String) -> SnapshotRestoreResult {
        SnapshotRestoreResult(checkpoint: nil, correction: message)
    }
}
