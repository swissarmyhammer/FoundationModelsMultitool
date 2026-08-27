// `SequentialKeys` — the counter that gives each in-flight record its key.
//
// `CancellationNotices` and `InFlightInnerCalls` each hold their in-flight
// tasks in a dictionary keyed by the order the task started, and each took its
// key the same way. Two copies of one counter can drift: a change made to one
// copy leaves the other as it was. The counter is here one time, and both types
// take their keys from it.
//
// A `final class` over a `Mutex`, and never an actor, because each caller takes
// its key from code that cannot `await` — a synchronous `onCancel` handler, or
// an `AsyncHostFunction` body the promise pump starts on whatever thread it
// likes.

import Synchronization

/// A counter that answers each key one time, in ascending order, and that any
/// thread can take a key from.
final class SequentialKeys: Sendable {
    /// The key the next ``take()`` answers.
    private let nextKey = Mutex(0)

    /// Creates a counter that starts at the first key.
    init() {}

    /// Takes the next key, and never answers that key again.
    ///
    /// - Returns: The key.
    func take() -> Int {
        nextKey.withLock { key -> Int in
            defer { key += 1 }
            return key
        }
    }
}
