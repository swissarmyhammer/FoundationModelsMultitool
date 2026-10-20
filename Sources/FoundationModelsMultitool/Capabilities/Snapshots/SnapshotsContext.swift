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

    /// The correction for an error of libgit2 or of the file system.
    ///
    /// - Parameter error: The error that the store threw.
    /// - Returns: The correction that the model reads.
    private static func failureCorrection(for error: any Error) -> String {
        "The snapshot operation failed: \(error). Call tools.snapshots.list to see the checkpoints."
    }
}

extension SnapshotError: CorrectiveFailure {

    /// The last sentence of each correction after which no snapshot
    /// operation of the session can give a value.
    private static let stopCallingSnapshots = "Do not call tools.snapshots again in this session."

    /// The correction that tells the model why the operation gave no value,
    /// and what to do next.
    ///
    /// The verbs of this capability call only the list, take and rollback
    /// operations of the store. Thus ``sessionKeyOpen``, ``invalidSessionKey``
    /// and ``unreadableTimeline`` come only from an open or a remove that a
    /// caller of ``SnapshotsContext/perform(_:)`` runs. Each case has its own
    /// text all the same.
    var correctiveMessage: String {
        switch self {
        case .unavailable:
            "No snapshots are available for this session: no session is bound to the call, or the working "
                + "folder of the session is not in a git work tree. \(Self.stopCallingSnapshots)"
        case .invalidCheckpoint(let index):
            "There is no checkpoint \(index). A valid index is from 0 (the baseline, the state when the "
                + "session opened) to the count of checkpoints. Call tools.snapshots.list to see the checkpoints "
                + "and their indexes."
        case .workingDirectoryMismatch:
            "The snapshots of this session key belong to a different working folder, thus no snapshot is "
                + "available for this working folder."
        case .timelineConflict:
            "Another writer changed the snapshot timeline of this session after this session read it, for "
                + "example a second app instance on the same session. The operation recorded no checkpoint, and "
                + "the checkpoints of this session are not current. \(Self.stopCallingSnapshots)"
        case .unreadableTimeline:
            "The snapshot timeline of this session holds a checkpoint that cannot be read, thus no snapshot is "
                + "available for this session. \(Self.stopCallingSnapshots)"
        case .sessionKeyOpen:
            "The snapshots of this session cannot be removed while a session has them open. The checkpoints did "
                + "not change. Call tools.snapshots.list to see the checkpoints."
        case .invalidSessionKey:
            "The session key of this session is not a valid name for its snapshots, thus no snapshot is "
                + "available for this session. \(Self.stopCallingSnapshots)"
        }
    }
}
