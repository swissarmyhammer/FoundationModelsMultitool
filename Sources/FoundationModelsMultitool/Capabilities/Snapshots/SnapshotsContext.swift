// `SnapshotsContext` — the one context of the snapshots capability: the
// shared store, and the read of the session key at call time.
//
// The capability does NOT get a session key when it is built. The registry is
// built before the session exists, and `MultiTool.forked()` gives the same
// tool to a fork. Thus each verb reads `HookSession.current?.sessionKey` when
// it runs. Router binds `HookSession.current` for each model call, and a fork
// in a different working directory has its own key.
//
// A failure stays IN BAND, as a `correction`. It is never thrown: a call with
// no bound session, each `SnapshotError` of the store, and an error of libgit2
// are each a fact that the model reads inside the same answer.

import Foundation
import FoundationModelsHooks

/// The context that each verb of the snapshots capability reads: the store
/// that the host gives to the capability.
struct SnapshotsContext: Sendable {

    /// The store that the capability and `SnapshotHook` share.
    let store: SnapshotStore

    /// Runs `operation` on the store for the session key of the bound
    /// session.
    ///
    /// The session key is read from `HookSession.current` at call time. When
    /// no session is bound, the operation does not run, and the result is the
    /// correction of ``SnapshotError/unavailable``.
    ///
    /// - Parameter operation: The store operation, which gets the store and
    ///   the session key.
    /// - Returns: The value of the operation, or the correction that says why
    ///   there is no value.
    /// - Throws: `CancellationError` when the calling task is cancelled. Each
    ///   other error becomes a correction.
    func perform<Value: Sendable>(
        _ operation: @Sendable (SnapshotStore, String) async throws -> Value
    ) async throws -> Result<Value, CorrectiveRejection> {
        guard let sessionKey = HookSession.current?.sessionKey else {
            return .failure(CorrectiveRejection(correctiveMessage: SnapshotError.unavailable.correctiveMessage))
        }
        do {
            return .success(try await operation(store, sessionKey))
        } catch let error as SnapshotError {
            return .failure(CorrectiveRejection(correctiveMessage: error.correctiveMessage))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(CorrectiveRejection(correctiveMessage: Self.failureCorrection(for: error)))
        }
    }

    /// Moves one checkpoint of the session key of the bound session with
    /// `operation`, and gives the moved checkpoint as the result of the
    /// `undo` or the `redo` verb.
    ///
    /// The `undo` and the `redo` verbs differ only in the store operation,
    /// thus each verb gives its operation to this one body.
    ///
    /// - Parameter operation: The store operation that moves the checkpoint:
    ///   `SnapshotStore.undo(sessionKey:)` or `SnapshotStore.redo(sessionKey:)`.
    ///   It gets the store and the session key.
    /// - Returns: The moved checkpoint, whose files are the restored files, or
    ///   the correction.
    /// - Throws: `CancellationError` when the calling task is cancelled.
    func restore(
        _ operation: @Sendable (SnapshotStore, String) async throws -> Checkpoint
    ) async throws -> SnapshotRestoreResult {
        try await perform(operation).resolve(
            corrective: SnapshotRestoreResult.corrective, then: SnapshotRestoreResult.restored)
    }

    /// The correction for an error of libgit2 or of the file system.
    ///
    /// - Parameter error: The error that the store threw.
    /// - Returns: The correction that the model reads.
    private static func failureCorrection(for error: any Error) -> String {
        "The snapshot operation failed: \(error). Call tools.snapshots.list to see the checkpoints."
    }
}

extension SnapshotError: CorrectiveFailure {

    /// The correction that tells the model why the operation gave no value,
    /// and what to do next.
    var correctiveMessage: String {
        switch self {
        case .unavailable:
            "No snapshots are available for this session: no session is bound to the call, or the working "
                + "folder of the session is not in a git work tree. Do not call tools.snapshots again in this "
                + "session."
        case .nothingToUndo:
            "There is no checkpoint to undo. Call tools.snapshots.list to see the checkpoints."
        case .nothingToRedo:
            "There is no undone checkpoint to redo. A change of the work tree after an undo clears the redo "
                + "list. Call tools.snapshots.list to see the checkpoints."
        case .invalidCheckpoint(let index):
            "There is no checkpoint \(index). Call tools.snapshots.list to see the checkpoints."
        case .workingDirectoryMismatch:
            "The snapshots of this session key belong to a different working folder, thus no snapshot is "
                + "available for this working folder."
        }
    }
}
