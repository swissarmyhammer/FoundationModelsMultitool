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
/// A test that must end one bound and hold the others — two bounds of
/// different length that sleep on one clock — calls ``open(sleepsOf:)``
/// instead: it opens the clock for the sleeps of one duration only.
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

        /// The duration the sleep asked for.
        let duration: Swift.Duration

        /// The continuation that ends the sleep.
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// One sleep that took its ticket and did not register yet.
    private struct Ticket {
        /// The number of the ticket.
        let number: Int

        /// The duration the sleep asked for.
        let duration: Swift.Duration
    }

    /// What a sleep does at the moment it registers.
    private enum Registration {
        /// The clock is open for the sleep: the sleep ends at once.
        case proceed

        /// The task of the sleep was cancelled first: the sleep throws.
        case cancelled

        /// The clock is closed for the sleep: the sleep waits for ``open()``.
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

        /// The durations ``open(sleepsOf:)`` opened the clock for.
        var openDurations: Set<Swift.Duration> = []

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

        /// Whether a sleep of `duration` ends at once.
        ///
        /// - Parameter duration: The duration the sleep asked for.
        /// - Returns: `true` after ``open()``, or after ``open(sleepsOf:)``
        ///   with this duration.
        func isOpen(for duration: Swift.Duration) -> Bool {
            isOpen || openDurations.contains(duration)
        }

        /// Takes every waiting sleep that `isReleased` selects out of
        /// ``waiting``, and moves the virtual instant to its deadline.
        ///
        /// - Parameter isReleased: Selects the sleeps that end.
        /// - Returns: The sleeps that end, for the caller to resume outside
        ///   the lock.
        mutating func release(where isReleased: (Sleeper) -> Bool) -> [Sleeper] {
            let released = waiting.filter { isReleased($0.value) }
            for (ticket, sleeper) in released {
                waiting[ticket] = nil
                reach(sleeper.deadline)
            }
            return Array(released.values)
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
    /// at once when the clock is already open for the delay.
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
            cancel(ticket: ticket.number)
        }
    }

    /// Ends every sleep that waits, and makes every later sleep end at once.
    func open() {
        let sleepers = state.withLock { current in
            current.isOpen = true
            return current.release { _ in true }
        }
        resume(sleepers)
    }

    /// Ends every sleep of `duration` that waits, and makes every later sleep
    /// of `duration` end at once. A sleep of any other duration still waits.
    ///
    /// - Parameter duration: The requested duration of the sleeps to end.
    func open(sleepsOf duration: Swift.Duration) {
        let sleepers = state.withLock { current in
            current.openDurations.insert(duration)
            return current.release { $0.duration == duration }
        }
        resume(sleepers)
    }

    /// Ends each of `sleepers`.
    ///
    /// - Parameter sleepers: The sleeps that end, already out of the state.
    private func resume(_ sleepers: [Sleeper]) {
        for sleeper in sleepers {
            sleeper.continuation.resume()
        }
    }

    /// Records one requested sleep, and gives it its ticket.
    ///
    /// - Parameter deadline: The instant the sleep asks for.
    /// - Returns: The ticket of the sleep.
    private func takeTicket(for deadline: ManualInstant) -> Ticket {
        state.withLock { current in
            let duration = current.currentInstant.duration(to: deadline)
            current.sleeps.append(duration)
            let number = current.nextTicket
            current.nextTicket += 1
            return Ticket(number: number, duration: duration)
        }
    }

    /// Ends the sleep of `ticket` at once, or holds it until ``open()``.
    ///
    /// - Parameters:
    ///   - ticket: The ticket of the sleep.
    ///   - deadline: The instant the sleep asks for.
    ///   - continuation: The continuation that ends the sleep.
    private func register(
        ticket: Ticket, deadline: ManualInstant, continuation: CheckedContinuation<Void, any Error>
    ) {
        let registration = state.withLock { current -> Registration in
            if current.cancelledTickets.remove(ticket.number) != nil {
                return .cancelled
            }
            if current.isOpen(for: ticket.duration) {
                current.reach(deadline)
                return .proceed
            }
            current.waiting[ticket.number] = Sleeper(
                deadline: deadline, duration: ticket.duration, continuation: continuation)
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
    /// - Parameter ticket: The number of the ticket of the cancelled sleep.
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
