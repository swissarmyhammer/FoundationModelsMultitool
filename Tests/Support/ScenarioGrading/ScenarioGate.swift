// `ScenarioGate` — a gate that a scenario runner opens at a fixed point of a
// run, and that a fixture tool waits on.
//
// No test may depend on time. A fixture that must answer "late" waits on this
// gate in place of a sleep, and the runner opens the gate at the point of the
// run that "late" means. Thus the order of the events is the order that the
// runner states, and no load of the machine can change it.
//
// The gate stands in the `ScenarioGrading` target, because the fixtures stand
// there, and the unit test target and the nested `IntegrationTests` package
// both take them.

import Synchronization
import TestConcurrency

/// A gate that holds each waiter until a scenario runner opens it. After it
/// opens, each wait returns at once.
///
/// ``open()`` is synchronous. ``wait()`` ends with `CancellationError` when
/// the task of the waiter is cancelled first, thus a run that ends before the
/// runner opens the gate does not leave a fixture call that never ends.
/// ``waitForWaiter()`` is the event that a fixture call reached its wait.
public final class ScenarioGate: Sendable {
    /// What one call of ``wait()`` does next.
    private enum WaitStart {
        /// The gate is open: the wait returns at once.
        case open

        /// The task was cancelled before the wait was recorded.
        case cancelled

        /// The wait continues until the gate opens or the task is cancelled.
        case waiting
    }

    /// Everything that ``open()``, the waiters and the watchers change.
    private struct State {
        /// Whether ``open()`` ran.
        var isOpen = false

        /// Each wait that did not end, by id.
        var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]

        /// The id of each wait whose task was cancelled before the wait was
        /// recorded.
        var cancelled: Set<Int> = []

        /// The id that the next wait gets.
        var nextID = 0

        /// Whether a call of ``wait()`` started.
        var hadWaiter = false
    }

    /// The state of the gate.
    private let state = Mutex(State())

    /// Each call of ``waitForWaiter()`` that did not end.
    private let waiterWatches = WaitList<Void>()

    /// Makes a closed gate.
    public init() {}

    /// Whether the gate is open.
    public var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    /// Opens the gate: each wait ends now, and each later wait returns at
    /// once. A second call does nothing.
    public func open() {
        let waiting = state.withLock { current -> [CheckedContinuation<Void, any Error>] in
            guard !current.isOpen else { return [] }
            current.isOpen = true
            defer { current.waiters.removeAll() }
            return Array(current.waiters.values)
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Waits until the gate opens. Returns at once when it is open.
    ///
    /// The call also ends each wait of ``waitForWaiter()``.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   gate opens.
    public func wait() async throws {
        let id = state.withLock { current -> Int in
            defer { current.nextID += 1 }
            current.hadWaiter = true
            return current.nextID
        }
        waiterWatches.resumeAll()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let start = state.withLock { current -> WaitStart in
                    let wasCancelled = current.cancelled.remove(id) != nil
                    if current.isOpen {
                        return .open
                    }
                    if wasCancelled {
                        return .cancelled
                    }
                    current.waiters[id] = continuation
                    return .waiting
                }
                switch start {
                case .open:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .waiting:
                    break
                }
            }
        } onCancel: {
            cancelWait(id: id)
        }
    }

    /// Waits until a call of ``wait()`` started. Returns at once when one
    /// already did.
    ///
    /// A test waits here to know that a fixture call reached its wait on the
    /// gate, and thus did not answer yet. A cancel of the task of the caller
    /// also ends the wait. The caller reads the run when it must know that a
    /// fixture call came.
    public func waitForWaiter() async {
        await waiterWatches.wait(for: (), unless: { state.withLock { $0.hadWaiter } })
    }

    /// Ends one wait with `CancellationError`, or records the cancel when the
    /// wait is not recorded yet.
    ///
    /// - Parameter id: The id of the wait.
    private func cancelWait(id: Int) {
        let waiter = state.withLock { current -> CheckedContinuation<Void, any Error>? in
            if let found = current.waiters.removeValue(forKey: id) {
                return found
            }
            if !current.isOpen {
                current.cancelled.insert(id)
            }
            return nil
        }
        waiter?.resume(throwing: CancellationError())
    }
}
