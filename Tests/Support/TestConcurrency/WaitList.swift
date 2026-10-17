// `WaitList` — the open waits for one event of a test double, each of which
// a cancel of its task also ends.
//
// Each wait of a test must also end on the failure event (test rule T1). The
// test doubles of the test support targets each kept a list of
// continuations that only their own event resumed. A test whose task was
// cancelled while it waited there left the continuation open, and the wait
// did not end. This file is that list, written one time with its cancel, and
// each double holds one.
//
// Test support, and no shipped target links it. It stands in this target
// because each test support target and the unit test target can link it.

import Synchronization

/// The open waits for one event, each with the condition that ends it.
///
/// A wait ends on the first of these:
/// - ``resume(where:)``, ``resumeAll()`` or ``resumeFirst()`` reaches it. The
///   wait returns `true`: the event came.
/// - ``endAll()`` reaches it. The wait returns `false`: the event cannot come
///   any more, for example because the stream that sends it finished.
/// - The task of the waiter is cancelled, also before the call. The wait
///   returns `false`.
///
/// Thus no continuation stays open, and a test that waits here fails and
/// does not hang when its event does not come.
///
/// The owner reads its own state in the `isMet` closure of
/// ``wait(for:unless:afterStoring:isolation:)``. The list calls that closure
/// under its lock, in the same step that stores the wait. An owner that
/// changes its state first and then resumes the list thus never loses a
/// wakeup, also when the owner is not an actor.
public final class WaitList<Condition: Sendable>: Sendable {
    /// One wait that did not end.
    private struct Waiter {
        /// The condition that ``resume(where:)`` tests.
        let condition: Condition

        /// The continuation that ends the wait.
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// Everything that the waits, the resumes and the cancels change.
    private struct State {
        /// Each wait that did not end, by id. The ids increase in arrival
        /// order.
        var waiters: [Int: Waiter] = [:]

        /// The id of each wait that started and is not stored or ended yet.
        var starting: Set<Int> = []

        /// The id of each starting wait whose task was cancelled.
        var cancelled: Set<Int> = []

        /// The id that the next wait gets.
        var nextID = 0
    }

    /// The state of the list.
    private let state = Mutex(State())

    /// Makes a list with no wait.
    public init() {}

    /// How many waits did not end.
    public var count: Int {
        state.withLock { $0.waiters.count }
    }

    /// Waits until a resume reaches this wait, `isMet` is already true, an
    /// ``endAll()`` reaches it, or the task is cancelled.
    ///
    /// - Parameters:
    ///   - condition: The condition that ``resume(where:)`` tests.
    ///   - isMet: Reads the state of the owner. When it is true, the wait
    ///     returns `true` at once. The list calls it under its lock.
    ///   - afterStoring: Runs after the wait is stored, before it suspends.
    ///   - isolation: The actor of the caller. The wait stays on it until it
    ///     suspends, thus the read of `isMet` and the store are one step of
    ///     that actor.
    /// - Returns: `true` when the event came. `false` when ``endAll()`` or a
    ///   cancel ended the wait.
    @discardableResult
    public func wait(
        for condition: Condition,
        unless isMet: () -> Bool = { false },
        afterStoring: () -> Void = {},
        isolation: isolated (any Actor)? = #isolation
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let id = state.withLock { current -> Int in
            defer { current.nextID += 1 }
            current.starting.insert(current.nextID)
            return current.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let endedAtOnce = state.withLock { current -> Bool? in
                    current.starting.remove(id)
                    if current.cancelled.remove(id) != nil {
                        return false
                    }
                    if isMet() {
                        return true
                    }
                    current.waiters[id] = Waiter(condition: condition, continuation: continuation)
                    return nil
                }
                guard let endedAtOnce else {
                    afterStoring()
                    return
                }
                continuation.resume(returning: endedAtOnce)
            }
        } onCancel: {
            cancelWait(id: id)
        }
    }

    /// Ends each wait whose condition `isMet` accepts. Each such wait
    /// returns `true`.
    ///
    /// - Parameter isMet: The test of the condition of one wait.
    public func resume(where isMet: (Condition) -> Bool) {
        let met = state.withLock { current -> [CheckedContinuation<Bool, Never>] in
            let ids = current.waiters.filter { isMet($0.value.condition) }.keys
            return ids.compactMap { current.waiters.removeValue(forKey: $0)?.continuation }
        }
        for continuation in met {
            continuation.resume(returning: true)
        }
    }

    /// Ends each wait. Each wait returns `true`.
    public func resumeAll() {
        resume { _ in true }
    }

    /// Ends the wait that came first. It returns `true`.
    ///
    /// - Returns: `true` when a wait ended. `false` when no wait was open.
    @discardableResult
    public func resumeFirst() -> Bool {
        let first = state.withLock { current -> CheckedContinuation<Bool, Never>? in
            guard let id = current.waiters.keys.min() else { return nil }
            return current.waiters.removeValue(forKey: id)?.continuation
        }
        first?.resume(returning: true)
        return first != nil
    }

    /// Ends each wait because the event cannot come any more. Each wait
    /// returns `false`.
    public func endAll() {
        let all = state.withLock { current -> [CheckedContinuation<Bool, Never>] in
            defer { current.waiters.removeAll() }
            return current.waiters.values.map(\.continuation)
        }
        for continuation in all {
            continuation.resume(returning: false)
        }
    }

    /// Ends one wait whose task was cancelled, or records the cancel when the
    /// wait is not stored yet.
    ///
    /// - Parameter id: The id of the wait.
    private func cancelWait(id: Int) {
        let waiter = state.withLock { current -> Waiter? in
            if let found = current.waiters.removeValue(forKey: id) {
                return found
            }
            if current.starting.contains(id) {
                current.cancelled.insert(id)
            }
            return nil
        }
        waiter?.continuation.resume(returning: false)
    }
}
