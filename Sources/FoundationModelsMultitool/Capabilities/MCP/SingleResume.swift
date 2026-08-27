// `SingleResume` — one continuation, two racing tasks, one resumption.
//
// A behavioral port of the private `SingleResume` class of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`. It
// stands in a file of its own because two extensions of `MCPServer`, in two
// files, race through it: the connect attempt against its timeout, and the
// bounded wait of the client-operation queue.

import Synchronization

/// Serializes the single resumption of a shared `CheckedContinuation` between
/// two racing tasks.
///
/// `MCPServer` races a connect attempt against its own timeout, and a queued
/// client operation against a grace period — two independent, un-joined
/// tasks, where the answer of the winner is the answer of the caller and the
/// loser keeps running to no effect. `CheckedContinuation.resume(with:)` traps
/// when it is called more than one time; this guards that with a `Mutex`, so
/// the task that finishes first wins and the later resume attempt is dropped,
/// with no data race over which one gets there first.
final class SingleResume<Value: Sendable, Failure: Error>: Sendable {
    /// The continuation, or `nil` once it was resumed.
    private let continuation: Mutex<CheckedContinuation<Value, Failure>?>

    /// Wraps `continuation` for exactly one resumption.
    ///
    /// - Parameter continuation: The continuation to resume at most one time.
    init(_ continuation: CheckedContinuation<Value, Failure>) {
        self.continuation = Mutex(continuation)
    }

    /// Resumes the wrapped continuation with `result`, or ignores a second
    /// resumption.
    ///
    /// - Parameter result: The result, or the error, to resume with.
    func resume(with result: Result<Value, Failure>) {
        let winner = continuation.withLock { stored -> CheckedContinuation<Value, Failure>? in
            defer { stored = nil }
            return stored
        }
        winner?.resume(with: result)
    }
}
