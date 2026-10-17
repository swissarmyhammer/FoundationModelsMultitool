// `ElicitationWaiters` — the open waits of one test hook of `MCPServer`, each
// for one URL-mode flow, by the id of the wait.
//
// It stands in a file of its own because two waits of
// `MCPServer+Elicitation.swift` share it, each with its own value type, and
// `MCPServer.swift` stores one instance for each wait.

/// The open waits of one test hook, each for one URL-mode flow, by the id of
/// the wait.
///
/// A wait records its continuation under a wait id from ``makeWaiterID()``.
/// ``resume(of:with:)`` ends each wait of a flow, and ``end(_:with:)`` ends
/// one wait — the cancel of that wait. Each continuation is removed before it
/// is resumed, so no continuation is resumed two times.
struct ElicitationWaiters<Value: Sendable>: Sendable {
    /// Each open wait, by the id of the wait: the wire id of the flow that it
    /// waits for, and its continuation.
    private var waiters: [Int: (elicitationId: String, continuation: CheckedContinuation<Value, Never>)] = [:]

    /// The id the next wait gets.
    private var nextWaiterID = 0

    /// `true` when no wait is open.
    var isEmpty: Bool { waiters.isEmpty }

    /// The number of open waits.
    var count: Int { waiters.count }

    /// Tells if a wait for the flow `elicitationId` is open.
    ///
    /// - Parameter elicitationId: The wire id of the flow.
    /// - Returns: `true` when at least one open wait waits for that flow.
    func contains(elicitationId: String) -> Bool {
        waiters.values.contains { $0.elicitationId == elicitationId }
    }

    /// Gives a new wait id, which no other wait of this instance has.
    ///
    /// - Returns: The id of the new wait.
    mutating func makeWaiterID() -> Int {
        defer { nextWaiterID += 1 }
        return nextWaiterID
    }

    /// Records `continuation` as the open wait `waiterID` for the flow
    /// `elicitationId`.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of the wait.
    ///   - waiterID: The id of the wait, from ``makeWaiterID()``.
    ///   - elicitationId: The wire id of the flow that the wait waits for.
    mutating func record(
        _ continuation: CheckedContinuation<Value, Never>,
        as waiterID: Int,
        for elicitationId: String
    ) {
        waiters[waiterID] = (elicitationId, continuation)
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

    /// Ends each open wait for the flow `elicitationId` with `value`.
    ///
    /// - Parameters:
    ///   - elicitationId: The wire id of the flow.
    ///   - value: The value each wait returns.
    mutating func resume(of elicitationId: String, with value: Value) {
        let matching = waiters.filter { $0.value.elicitationId == elicitationId }
        for waiterID in matching.keys {
            end(waiterID, with: value)
        }
    }
}
