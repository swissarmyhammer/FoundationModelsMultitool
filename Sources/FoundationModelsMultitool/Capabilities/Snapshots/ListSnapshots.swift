// `ListSnapshots` — the `tools.snapshots.list` verb.
//
// The verb takes no argument, and gives each checkpoint of the session key of
// the bound session, oldest first. A rollback is a checkpoint too, thus the
// list keeps each checkpoint after a rollback.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// snapshots capability, in the pattern of `Capabilities/Git/Status.swift`. The
// capability supplies the noun, thus this verb's `name` is the bare `list` and
// the surface path renders as `tools.snapshots.list`.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The arguments of `tools.snapshots.list`: none.
@Generable
struct ListSnapshotsArguments {}

/// The result of `tools.snapshots.list`: the checkpoints of the session, or
/// the correction that says why there is no list.
///
/// `correction` and the list are exclusive. A correction carries no
/// checkpoint.
@Generable(
    description: "the checkpoints of the session, oldest first, or the correction that says why there is no list.")
struct ListSnapshotsResult: SnapshotsVerbResult {

    /// The checkpoints, oldest first.
    @Guide(
        description:
            "The checkpoints of the session, oldest first. The index of each one is the index that "
            + "tools.snapshots.rollback takes.")
    var checkpoints: [SnapshotCheckpoint] = []

    /// Why there is no list, or `nil` when the list stands.
    @Guide(description: "Why there is no list; null when the list stands.")
    var correction: String?
}

extension ListSnapshots {

    // MARK: Execution

    /// Reads the checkpoints of the session key of the bound session.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The checkpoints, or the correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: ListSnapshotsArguments) async throws -> ListSnapshotsResult {
        try await context.perform { store, sessionKey in
            try await store.checkpoints(sessionKey: sessionKey)
        }.resolve(corrective: ListSnapshotsResult.corrective, then: Self.result(of:))
    }

    // MARK: Steps

    /// The result of a list.
    ///
    /// - Parameter checkpoints: The checkpoints of the store, oldest first.
    /// - Returns: The result.
    private static func result(of checkpoints: [Checkpoint]) -> ListSnapshotsResult {
        ListSnapshotsResult(checkpoints: checkpoints.map(SnapshotCheckpoint.init), correction: nil)
    }
}

/// Gives the checkpoints of the session.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { checkpoints } = await tools.snapshots.list({});
/// ```
struct ListSnapshots: Tool {

    /// The verb this tool renders as, which the snapshots noun stands in
    /// front of: `tools.snapshots.list`.
    let name = "list"

    /// The usage instructions, as the model reads them.
    let description = """
        list gives the checkpoints of this session, oldest first. A checkpoint is a recorded change of the \
        work tree: its index (from 1), its trigger (the tool call, the label of tools.snapshots.take, a \
        rollback, or pending), the changed files, and the date. Call list first to find the index for \
        tools.snapshots.rollback. A session with no snapshots comes back as a correction rather than as an \
        error — read it and act on it.
        """

    /// The session context this verb reads against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
