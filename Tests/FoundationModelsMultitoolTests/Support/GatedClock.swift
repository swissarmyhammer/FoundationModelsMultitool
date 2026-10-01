// `GatedClock` — a clock whose sleeps end only when the test opens it.
//
// `ManualClock` ends each sleep at once. That is right for a delay a test
// wants to skip, and wrong for a deadline the test must hold back: a time
// limit, a bounded wait, a timed stage. A deadline that sleeps on the real
// clock races the test under machine load. A deadline that sleeps on this
// clock waits until the test calls `open()`. Thus the order of the events is
// the order the test states, and no load can change it.

import Synchronization

/// A `Clock` whose `sleep(until:tolerance:)` waits until ``open()``, and
/// then returns at once — for every sleep that waits, and for every later
/// sleep.
///
/// The clock records each requested duration, in call order, so a test can
/// read which bound the code under test chose. A sleep whose task is
/// cancelled throws `CancellationError`, as the sleep of a real clock does.
/// Thus a task group that cancels its timer still ends.
///
/// State lives behind a `Mutex`, because ``sleep(until:tolerance:)`` — a
/// `Clock` requirement — is itself `async`.
final class GatedClock: Clock, Sendable {
    typealias Duration = Swift.Duration

    /// One sleep that waits for ``open()``.
    private struct Sleeper {
        /// The instant the sleep asked for.
        let deadline: ManualInstant

        /// The continuation that ends the sleep.
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// What a sleep does at the moment it registers.
    private enum Registration {
        /// The clock is open: the sleep ends at once.
        case proceed

        /// The task of the sleep was cancelled first: the sleep throws.
        case cancelled

        /// The clock is closed: the sleep waits for ``open()``.
        case wait
    }

    /// The state the mutex guards.
    private struct State {
        /// The current virtual instant. It moves only when a sleep ends.
        var currentInstant = ManualInstant(offset: .zero)

        /// Every requested sleep, in call order.
        var sleeps: [Swift.Duration] = []

        /// Whether ``open()`` was called.
        var isOpen = false

        /// The sleeps that wait for ``open()``, by ticket.
        var waiting: [Int: Sleeper] = [:]

        /// The tickets whose task was cancelled before the sleep registered.
        var cancelledTickets: Set<Int> = []

        /// The ticket the next sleep takes.
        var nextTicket = 0

        /// Moves ``currentInstant`` to `deadline` when `deadline` is later.
        ///
        /// - Parameter deadline: The instant a sleep that ends asked for.
        mutating func reach(_ deadline: ManualInstant) {
            if deadline > currentInstant {
                currentInstant = deadline
            }
        }
    }

    /// The guarded state.
    private let state = Mutex(State())

    /// Every duration requested through `sleep(until:tolerance:)`, in call
    /// order.
    var recordedSleeps: [Swift.Duration] {
        state.withLock { $0.sleeps }
    }

    /// The current virtual instant. It moves only when a sleep ends.
    var now: ManualInstant {
        state.withLock { $0.currentInstant }
    }

    /// No meaningful minimum resolution: a gated clock has no real
    /// scheduling granularity.
    var minimumResolution: Swift.Duration { .zero }

    /// Records the requested delay, and waits until ``open()`` — or returns
    /// at once when the clock is already open.
    ///
    /// - Parameters:
    ///   - deadline: The instant to sleep until.
    ///   - tolerance: Ignored — a gated clock has no scheduling jitter.
    /// - Throws: `CancellationError` when the task of the sleep is cancelled
    ///   before the clock opens.
    func sleep(until deadline: ManualInstant, tolerance: Swift.Duration?) async throws {
        let ticket = takeTicket(for: deadline)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                register(ticket: ticket, deadline: deadline, continuation: continuation)
            }
        } onCancel: {
            cancel(ticket: ticket)
        }
    }

    /// Ends every sleep that waits, and makes every later sleep end at once.
    func open() {
        let sleepers = state.withLock { current in
            current.isOpen = true
            let sleepers = Array(current.waiting.values)
            current.waiting = [:]
            for sleeper in sleepers {
                current.reach(sleeper.deadline)
            }
            return sleepers
        }
        for sleeper in sleepers {
            sleeper.continuation.resume()
        }
    }

    /// Records one requested sleep, and gives it its ticket.
    ///
    /// - Parameter deadline: The instant the sleep asks for.
    /// - Returns: The ticket of the sleep.
    private func takeTicket(for deadline: ManualInstant) -> Int {
        state.withLock { current in
            current.sleeps.append(current.currentInstant.duration(to: deadline))
            let ticket = current.nextTicket
            current.nextTicket += 1
            return ticket
        }
    }

    /// Ends the sleep of `ticket` at once, or holds it until ``open()``.
    ///
    /// - Parameters:
    ///   - ticket: The ticket of the sleep.
    ///   - deadline: The instant the sleep asks for.
    ///   - continuation: The continuation that ends the sleep.
    private func register(
        ticket: Int, deadline: ManualInstant, continuation: CheckedContinuation<Void, any Error>
    ) {
        let registration = state.withLock { current -> Registration in
            if current.cancelledTickets.remove(ticket) != nil {
                return .cancelled
            }
            if current.isOpen {
                current.reach(deadline)
                return .proceed
            }
            current.waiting[ticket] = Sleeper(deadline: deadline, continuation: continuation)
            return .wait
        }
        switch registration {
        case .proceed:
            continuation.resume()
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        case .wait:
            break
        }
    }

    /// Ends the sleep of `ticket` with `CancellationError`, or marks the
    /// ticket so that the sleep throws when it registers.
    ///
    /// - Parameter ticket: The ticket of the cancelled sleep.
    private func cancel(ticket: Int) {
        let sleeper = state.withLock { current -> Sleeper? in
            if let sleeper = current.waiting.removeValue(forKey: ticket) {
                return sleeper
            }
            current.cancelledTickets.insert(ticket)
            return nil
        }
        sleeper?.continuation.resume(throwing: CancellationError())
    }
}
