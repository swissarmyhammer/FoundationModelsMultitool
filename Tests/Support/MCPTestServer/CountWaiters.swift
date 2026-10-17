// `CountWaiters` — the open waits for a count of recorded items of one
// `ScriptedServer` record.
//
// Test support — see the header of `ScriptedServer.swift`. A test that waits
// for a recorded notification or a received elicitation result waits on an
// event that the record sends. One shape serves each record, thus each wait
// ends the same way: on the count, or on a cancel of the task of the caller.

/// The open waits for a count of recorded items, and the cancels that came
/// before their wait was stored.
///
/// A value type that the `ScriptedServer` actor holds, so the actor isolation
/// guards it.
struct CountWaiters<Item: Sendable> {
    /// One wait that did not end.
    private struct Waiter {
        /// The count of recorded items that ends the wait.
        let count: Int

        /// The continuation that ends the wait with the recorded items.
        let continuation: CheckedContinuation<[Item], Never>
    }

    /// Each wait that did not end, by id.
    private var waiters: [Int: Waiter] = [:]

    /// The id of each wait whose task was cancelled before the wait was
    /// stored.
    private var cancelled: Set<Int> = []

    /// The id that the next wait gets.
    private var nextID = 0

    /// Gives the id of a new wait.
    ///
    /// - Returns: The id.
    mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Stores one wait, or ends it at once when `recorded` already reaches
    /// its count or its task was already cancelled.
    ///
    /// - Parameters:
    ///   - id: The id of the wait.
    ///   - count: The count of recorded items that ends the wait.
    ///   - recorded: The items recorded now.
    ///   - continuation: The continuation that ends the wait.
    mutating func store(
        id: Int, count: Int, recorded: [Item], continuation: CheckedContinuation<[Item], Never>
    ) {
        if cancelled.remove(id) != nil || recorded.count >= count {
            continuation.resume(returning: recorded)
            return
        }
        waiters[id] = Waiter(count: count, continuation: continuation)
    }

    /// Ends each wait whose count `recorded` reaches.
    ///
    /// - Parameter recorded: The items recorded now.
    mutating func resume(reachedBy recorded: [Item]) {
        let reached = waiters.filter { $0.value.count <= recorded.count }
        for (id, waiter) in reached {
            waiters[id] = nil
            waiter.continuation.resume(returning: recorded)
        }
    }

    /// Ends one wait whose task was cancelled, or marks the wait so that it
    /// ends when it is stored.
    ///
    /// - Parameters:
    ///   - id: The id of the wait.
    ///   - recorded: The items recorded now.
    mutating func cancel(id: Int, recorded: [Item]) {
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.continuation.resume(returning: recorded)
        } else {
            cancelled.insert(id)
        }
    }
}
