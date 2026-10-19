// `ListSnapshots` — the `tools.snapshots.list` verb.
//
// The verb takes no argument, and gives each checkpoint of the session key of
// the bound session, oldest first. An undone checkpoint is not in the list.
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
struct ListSnapshotsResult {

    /// The checkpoints, oldest first.
    @Guide(description: "The checkpoints of the session, oldest first. An undone checkpoint is not in the list.")
    var checkpoints: [SnapshotCheckpoint]

    /// Whether an undone checkpoint is available to redo.
    @Guide(description: "True when tools.snapshots.redo has an undone checkpoint to put back.")
    var isRedoAvailable: Bool

    /// Why there is no list, or `nil` when the list stands.
    @Guide(description: "Why there is no list; null when the list stands.")
    var correction: String?
}

extension ListSnapshots {

    // MARK: Execution

    /// Reads the checkpoints of the session key of the bound session, and
    /// whether a redo is available.
    ///
    /// - Parameter arguments: None.
    /// - Returns: The checkpoints and the redo state, or the correction.
    /// - Throws: `CancellationError` when the call is cancelled.
    func call(arguments: ListSnapshotsArguments) async throws -> ListSnapshotsResult {
        try await context.perform { store, sessionKey in
            let checkpoints = try await store.checkpoints(sessionKey: sessionKey)
            let isRedoAvailable = try await Self.isRedoAvailable(in: store, sessionKey: sessionKey)
            return ListSnapshotsResult(
                checkpoints: checkpoints.map(SnapshotCheckpoint.init), isRedoAvailable: isRedoAvailable,
                correction: nil)
        }.resolve(corrective: Self.corrective, then: { $0 })
    }

    // MARK: Steps

    /// Whether the redo stack of `sessionKey` holds a checkpoint.
    ///
    /// The list reads the checkpoints first, and the redo stack in a second
    /// call. The key can close between the two calls. The checkpoints that
    /// the first call gave still stand, thus ``SnapshotError/unavailable``
    /// from the second call means that no redo is available, and not that
    /// there is no list.
    ///
    /// - Parameters:
    ///   - store: The store to read.
    ///   - sessionKey: The session key.
    /// - Returns: `true` when a redo is available.
    /// - Throws: Each error of the store other than
    ///   ``SnapshotError/unavailable``.
    private static func isRedoAvailable(in store: SnapshotStore, sessionKey: String) async throws -> Bool {
        do {
            return try await !store.undoneCheckpoints(sessionKey: sessionKey).isEmpty
        } catch SnapshotError.unavailable {
            return false
        }
    }

    /// A result that carries only a correction.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``ListSnapshotsResult``.
    private static func corrective(_ message: String) -> ListSnapshotsResult {
        ListSnapshotsResult(checkpoints: [], isRedoAvailable: false, correction: message)
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
        work tree: its index (from 1), its trigger (the tool call, the label of tools.snapshots.take, or \
        pending), the changed files, and the date. An undone checkpoint is not in the list; isRedoAvailable \
        is true when tools.snapshots.redo can put an undone checkpoint back. A session with no \
        snapshots comes back as a correction rather than as an error — read it and act on it.
        """

    /// The session context this verb reads against, which the snapshots
    /// capability owns.
    let context: SnapshotsContext
}
