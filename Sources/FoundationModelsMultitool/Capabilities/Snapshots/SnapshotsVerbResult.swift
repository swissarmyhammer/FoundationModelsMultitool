// `SnapshotsVerbResult` — the shared builders of the results of the
// snapshots verbs.
//
// Each verb of the capability gives a result that carries its value or a
// correction. The verbs must build the correction-only result in the same
// shape, and `take` and `rollback` must build the "no change" result in the
// same shape. These protocols hold each builder one time. Thus the shape
// cannot drift apart between the verbs.

import FoundationModelsHooks

/// A result of a snapshots verb that can carry only a correction.
///
/// A conforming type gives each stored property other than `correction` an
/// empty default value. Thus `init()` makes the empty result, and
/// ``corrective(_:)`` adds only the correction to it.
protocol SnapshotsVerbResult {

    /// Makes the empty result: no value and no correction.
    init()

    /// Why the verb gave no value, or `nil` when the verb gave its value.
    var correction: String? { get set }
}

extension SnapshotsVerbResult {

    /// A result that carries only a correction.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The empty result with `message` as its correction.
    static func corrective(_ message: String) -> Self {
        var result = Self()
        result.correction = message
        return result
    }
}

/// A result of a snapshots verb that can make a checkpoint: the new
/// checkpoint, or "no change", or a correction.
protocol SnapshotCheckpointResult: SnapshotsVerbResult {

    /// Makes a result from its three fields.
    ///
    /// - Parameters:
    ///   - checkpoint: The new checkpoint, or `nil` when no checkpoint was
    ///     made.
    ///   - isUnchanged: Whether the work tree had no change, thus no
    ///     checkpoint was made.
    ///   - correction: Why the verb gave no value, or `nil`.
    init(checkpoint: SnapshotCheckpoint?, isUnchanged: Bool, correction: String?)
}

extension SnapshotCheckpointResult {

    /// The result of a store operation that makes a checkpoint.
    ///
    /// - Parameter checkpoint: The new checkpoint, or `nil` when the store
    ///   found no change.
    /// - Returns: The new checkpoint, or "no change".
    static func result(of checkpoint: SnapshotCheckpoint?) -> Self {
        Self(checkpoint: checkpoint, isUnchanged: checkpoint == nil, correction: nil)
    }
}
