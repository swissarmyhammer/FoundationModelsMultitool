// `TakeSnapshot` — the `tools.snapshots.take` verb.
//
// The verb records the state of the work tree of the session key of the bound
// session, with an optional label. When no file changed after the last
// snapshot, the store makes no checkpoint, and the result says "no change".
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// snapshots capability, in the pattern of `Capabilities/Git/Status.swift`.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The arguments of `tools.snapshots.take`: an optional label.
@Generable
struct TakeSnapshotArguments {

    /// The label of the checkpoint, or `nil` for no label.
    @Guide(description: "A short label for the checkpoint, for example 'before refactor'. Optional.")
    var label: String?
}

/// The result of `tools.snapshots.take`: the new checkpoint, "no change", or
/// the correction that says why no snapshot was taken.
@Generable(
    description: "the new checkpoint, or isUnchanged when no file changed after the last snapshot, or the "
        + "correction that says why no snapshot was taken.")
struct TakeSnapshotResult: SnapshotCheckpointResult {

    /// The new checkpoint, or `nil` when no checkpoint was made.
    @Guide(description: "The new checkpoint; null when no checkpoint was made.")
    var checkpoint: SnapshotCheckpoint?

    /// Whether no file changed after the last snapshot.
    @Guide(description: "True when no file changed after the last snapshot, thus no checkpoint was made.")
    var isUnchanged = false

    /// Why no snapshot was taken, or `nil` when the snapshot was taken.
    @Guide(description: "Why no snapshot was taken; null when the snapshot was taken.")
    var correction: String?
}

extension TakeSnapshot {

    // MARK: Execution

    /// Records the state of the work tree of the session key of the bound
    /// session, for that session as the owner.
    ///
    /// - Parameter arguments: The optional label.
    /// - Returns: The new checkpoint, "no change", or the correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: TakeSnapshotArguments) async throws -> TakeSnapshotResult {
        let trigger = SnapshotTrigger.manual(label: arguments.label)
        return try await context.perform { [context] store, sessionKey, owner in
            await context.modelCheckpoint(try await store.take(sessionKey: sessionKey, owner: owner, trigger: trigger))
        }.resolve(corrective: TakeSnapshotResult.corrective, then: TakeSnapshotResult.result(of:))
    }
}

/// Records the state of the work tree as a new checkpoint.
///
/// ```swift
/// // In a snippet the model writes:
/// //   await tools.snapshots.take({ label: "before refactor" });
/// ```
struct TakeSnapshot: Tool {

    /// The verb this tool renders as, which the snapshots noun stands in
    /// front of: `tools.snapshots.take`.
    let name = "take"

    /// The usage instructions, as the model reads them.
    let description = """
        take records the state of the work tree as a new checkpoint, with an optional label. Each tool call \
        that changes files already takes a snapshot, thus call take only to mark a point, for example before \
        a risky change. When no file changed after the last snapshot, no checkpoint is made and isUnchanged \
        is true. A session with no snapshots comes back as a correction rather than as an error — read it \
        and act on it.
        """

    /// The session context this verb writes against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
