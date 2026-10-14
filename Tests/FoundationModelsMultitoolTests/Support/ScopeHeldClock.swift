// `ScopeHeldClock` — a clock that holds only the sleeps of the tasks that a
// test marks.
//
// `GatedClock` holds each sleep until the test opens it, and it can select a
// sleep by its duration or by the order in which the clock recorded it. Two
// bounds of the same duration that the code under test asks for at the same
// time, in two tasks, have no fixed order, thus neither selection can hold one
// of them and end the other. This clock selects by task: a task that the
// test starts under ``ScopeHeldClock/$holdsSleeps`` gives that mark to each
// child task and to each unstructured task it starts, and each sleep of those
// tasks waits until ``ScopeHeldClock/open()``. Each other sleep ends at once.

import Synchronization

/// A `Clock` whose `sleep(until:tolerance:)` ends at once, except a sleep
/// that runs under ``holdsSleeps``: that sleep waits until ``open()``.
///
/// The clock records each requested duration, in call order, so a test can
/// read whether the code under test asked for a bound at all. A held sleep
/// whose task is cancelled throws `CancellationError`, as the sleep of a real
/// clock does.
final class ScopeHeldClock: Clock, Sendable {
    typealias Duration = Swift.Duration

    /// Whether a sleep of the current task waits until ``open()``. A test
    /// sets it with `$holdsSleeps.withValue(true)` around the call that starts
    /// the tasks to hold. An unstructured `Task` copies the value of the task
    /// that starts it.
    @TaskLocal static var holdsSleeps: Bool = false

    /// The state the mutex guards.
    private struct State {
        /// The current virtual instant. It moves only when a sleep ends.
        var currentInstant = ManualInstant(offset: .zero)

        /// Every requested sleep, in call order.
        var sleeps: [Swift.Duration] = []
    }

    /// The guarded state.
    private let state = Mutex(State())

    /// The gate that each held sleep waits on.
    private let gate = TestGate()

    /// Every duration requested through `sleep(until:tolerance:)`, in call
    /// order.
    var recordedSleeps: [Swift.Duration] {
        state.withLock { $0.sleeps }
    }

    /// The current virtual instant. It moves only when a sleep ends.
    var now: ManualInstant {
        state.withLock { $0.currentInstant }
    }

    /// No meaningful minimum resolution: this clock has no real scheduling
    /// granularity.
    var minimumResolution: Swift.Duration { .zero }

    /// Records the requested delay. Returns at once, or, when the current
    /// task runs under ``holdsSleeps``, waits until ``open()``.
    ///
    /// - Parameters:
    ///   - deadline: The instant to sleep until.
    ///   - tolerance: Ignored — this clock has no scheduling jitter.
    /// - Throws: `CancellationError` when the task of a held sleep is
    ///   cancelled before the clock opens.
    func sleep(until deadline: ManualInstant, tolerance: Swift.Duration?) async throws {
        state.withLock { current in
            current.sleeps.append(current.currentInstant.duration(to: deadline))
        }
        if Self.holdsSleeps {
            try await gate.wait()
        }
        state.withLock { current in
            if deadline > current.currentInstant {
                current.currentInstant = deadline
            }
        }
    }

    /// Ends every held sleep, and makes every later held sleep end at once.
    func open() {
        gate.open()
    }
}
