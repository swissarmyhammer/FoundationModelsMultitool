// `TestHookWaiters` — the open waits of one wait of an actor, each by the id
// of the wait, with the detail that the wait waits for.
//
// It stands in a file of its own because each store of the waits of
// `MCPServer` and of `ShellState` is one instance of it, and
// `TestHookWait.suspend(on:in:detail:cancelValue:resolvedValue:didRecord:)`
// records and ends each wait through it. Thus the steps that give a wait its
// id, record it, and end it by its id have one implementation.

/// The open waits of one wait of an actor, each by the id of the wait, with
/// the detail that the wait waits for.
///
/// A wait records its continuation under a wait id from ``makeWaiterID()``.
/// ``resume(where:with:)`` and ``resumeAll(with:)`` end each wait that they
/// select, and ``end(_:with:)`` ends one wait — the cancel of that wait. Each
/// continuation is removed before it is resumed, so no continuation is
/// resumed two times, and a resume that runs code of the owner finds no wait
/// to end a second time.
struct TestHookWaiters<Value: Sendable, Detail: Sendable>: Sendable {
    /// Each open wait, by the id of the wait: the detail that it waits for,
    /// and its continuation.
    private var waiters: [Int: (detail: Detail, continuation: CheckedContinuation<Value, Never>)] = [:]

    /// The id the next wait gets.
    private var nextWaiterID = 0

    /// `true` when no wait is open.
    var isEmpty: Bool { waiters.isEmpty }

    /// The number of open waits.
    var count: Int { waiters.count }

    /// Tells if an open wait waits for a detail that `isMatch` accepts.
    ///
    /// - Parameter isMatch: Whether the given detail is the one to find.
    /// - Returns: `true` when at least one open wait has such a detail.
    func contains(where isMatch: (Detail) -> Bool) -> Bool {
        waiters.values.contains { isMatch($0.detail) }
    }

    /// Gives a new wait id, which no other wait of this instance has.
    ///
    /// - Returns: The id of the new wait.
    mutating func makeWaiterID() -> Int {
        defer { nextWaiterID += 1 }
        return nextWaiterID
    }

    /// Records `continuation` as the open wait `waiterID` for `detail`.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of the wait.
    ///   - waiterID: The id of the wait, from ``makeWaiterID()``.
    ///   - detail: The detail that the wait waits for.
    mutating func record(
        _ continuation: CheckedContinuation<Value, Never>,
        as waiterID: Int,
        detail: Detail
    ) {
        waiters[waiterID] = (detail, continuation)
    }

    /// Ends the wait `waiterID` with `value`. A no-op when the wait ended
    /// before.
    ///
    /// - Parameters:
    ///   - waiterID: The id of the wait.
    ///   - value: The value the wait returns.
    mutating func end(_ waiterID: Int, with value: Value) {
        waiters.removeValue(forKey: waiterID)?.continuation.resume(returning: value)
    }

    /// Ends each open wait whose detail `isEnded` accepts with `value`.
    ///
    /// Each selected wait leaves the store before the first resume.
    ///
    /// - Parameters:
    ///   - isEnded: Whether the wait for the given detail ends now.
    ///   - value: The value each ended wait returns.
    mutating func resume(where isEnded: (Detail) -> Bool, with value: Value) {
        let ended = waiters.filter { isEnded($0.value.detail) }
        for waiterID in ended.keys {
            waiters[waiterID] = nil
        }
        for waiter in ended.values {
            waiter.continuation.resume(returning: value)
        }
    }

    /// Ends each open wait with `value`.
    ///
    /// - Parameter value: The value each wait returns.
    mutating func resumeAll(with value: Value) {
        resume(where: { _ in true }, with: value)
    }
}
