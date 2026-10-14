// `TestGate`, `TestCountdown` and `HeldCall` — the events that a test waits
// on in place of a sleep, a clock wait or a poll.
//
// No test may depend on time. A test that must know that a call started, that
// a call ended, or that a call can go on now, waits on one of these objects.
// The test, or the code under test at a fixed point, opens the object. A wait
// that the object never ends stops only when the task is cancelled.

import Synchronization

/// A gate that holds each waiter until a test, or the code under test at a
/// fixed point, opens it. After it opens, each wait returns at once.
///
/// ``open()`` is synchronous. Thus a synchronous host function, a lock-guarded
/// fixture or a `URLProtocol` callback can open the gate. ``wait()`` ends with
/// `CancellationError` when the task of the waiter is cancelled first. A gate
/// that never opens is thus a call that never completes and that a cancel
/// still ends.
final class TestGate: Sendable {
    /// What one call of ``wait()`` does next.
    private enum WaitStart {
        /// The gate is open: the wait returns at once.
        case open

        /// The task was cancelled before the wait was recorded.
        case cancelled

        /// The wait continues until the gate opens or the task is cancelled.
        case waiting
    }

    /// Everything that ``open()`` and the waiters change.
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
    }

    /// The state of the gate.
    private let state = Mutex(State())

    /// Makes a closed gate.
    init() {}

    /// Whether the gate is open.
    var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    /// Opens the gate: each wait ends now, and each later wait returns at
    /// once. A second call does nothing.
    func open() {
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
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   gate opens.
    func wait() async throws {
        let id = state.withLock { current -> Int in
            defer { current.nextID += 1 }
            return current.nextID
        }
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

/// A count of arrivals that opens a gate when the last arrival comes.
///
/// A test that must know that each of a fixed number of callers reached a
/// point waits on it, and each caller calls ``arrive()`` at that point.
final class TestCountdown: Sendable {
    /// How many arrivals are still to come.
    private let remaining: Mutex<Int>

    /// The gate that the last arrival opens.
    private let completed = TestGate()

    /// Makes a countdown for `count` arrivals.
    ///
    /// - Parameter count: How many arrivals open the gate. A count of zero or
    ///   less opens it at once.
    init(count: Int) {
        remaining = Mutex(count)
        if count <= 0 {
            completed.open()
        }
    }

    /// Records one arrival, and opens the gate when it is the last one.
    func arrive() {
        let isLast = remaining.withLock { count -> Bool in
            count -= 1
            return count == 0
        }
        if isLast {
            completed.open()
        }
    }

    /// Waits until each arrival came.
    ///
    /// - Throws: `CancellationError` when the task is cancelled first.
    func wait() async throws {
        try await completed.wait()
    }
}

/// A call that reports that it came, and then waits until the test lets it go
/// on.
///
/// A fixture calls ``pass()`` where a sleep made its call slow before. The
/// test waits on ``arrival``, does what it must do while the call is
/// pending, and then opens ``release``. After ``release`` opens, each later
/// call passes at once.
final class HeldCall: Sendable {
    /// The gate that the first call opens when it comes.
    let arrival = TestGate()

    /// The gate that the test opens to let each call go on.
    let release: TestGate

    /// Makes a held call.
    ///
    /// - Parameter release: The gate that lets each call go on. The default
    ///   is a new gate that only the test opens.
    init(release: TestGate = TestGate()) {
        self.release = release
    }

    /// Opens ``arrival``, and waits until ``release`` opens.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before
    ///   ``release`` opens.
    func pass() async throws {
        arrival.open()
        try await release.wait()
    }

    /// Waits until a call came, and then lets each call go on.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before a call
    ///   came.
    func releaseOnArrival() async throws {
        try await arrival.wait()
        release.open()
    }
}
