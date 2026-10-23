// `SnapshotCheckpoint` — one checkpoint of the store, as each verb of the
// snapshots capability writes it.
//
// A `Checkpoint` of FoundationModelsHooks carries two tree IDs that the model
// cannot use. This value carries what the model reads: the index, the
// trigger as text, the changed files, the date in ISO 8601 (UTC) — the same
// form as the dates of the git verbs — and the session that made it.

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
            + "tools.snapshots.take, 'rollback to <index>' for tools.snapshots.rollback, 'pending' for a "
            + "change that a rollback recorded first, or 'changed while closed' for a change that occurred "
            + "while the app was not running.")
    var trigger: String

    /// The files that the checkpoint changed.
    @Guide(description: "The files that the checkpoint changed, relative to the work tree.")
    var files: [String]

    /// The time of the snapshot.
    @Guide(description: "The time of the snapshot, ISO 8601 in UTC.")
    var date: String

    /// The session that made the checkpoint.
    @Guide(
        description:
            "The session that made the checkpoint: this session, or another session in the same working "
            + "directory, which shares these checkpoints.")
    var owner: String
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
            date: Self.dateStyle.format(checkpoint.date), owner: checkpoint.owner)
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
        case .rollback(let index):
            "rollback to \(index)"
        case .changedWhileClosed:
            "changed while closed"
        }
    }
}
