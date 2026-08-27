// `ManualClock` — a clock whose sleeps never wait.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/ManualClock.swift`.

import Synchronization

/// An `InstantProtocol` conformance that tracks elapsed time as a plain
/// `Duration` offset from an arbitrary zero point — the `Instant` type of
/// ``ManualClock``.
struct ManualInstant: InstantProtocol {
    /// The elapsed time since the zero point of ``ManualClock``.
    var offset: Duration

    /// Orders instants by their offset from the zero point.
    static func < (lhs: ManualInstant, rhs: ManualInstant) -> Bool {
        lhs.offset < rhs.offset
    }

    /// Returns an instant `duration` after this one.
    ///
    /// - Parameter duration: The amount of time to advance by.
    /// - Returns: A new instant `duration` later than `self`.
    func advanced(by duration: Duration) -> ManualInstant {
        ManualInstant(offset: offset + duration)
    }

    /// The amount of time between this instant and `other`.
    ///
    /// - Parameter other: The instant to measure the distance to.
    /// - Returns: The offset of `other` minus the offset of this instant.
    func duration(to other: ManualInstant) -> Duration {
        other.offset - offset
    }
}

/// A `Clock` whose `sleep(until:tolerance:)` never waits in real wall-clock
/// time — it advances its own instant to the requested deadline, records the
/// requested duration, and returns at once.
///
/// The retry loop of `MCPServer.connect(via:backoffPolicy:)` sleeps between
/// attempts on an injected `any Clock<Duration>`, so a test substitutes this
/// clock, drives a full multi-attempt exponential-backoff schedule with no
/// real delay, and asserts on ``recordedSleeps`` — the exact schedule
/// requested.
///
/// State lives behind a `Mutex`, because ``sleep(until:tolerance:)`` — a
/// `Clock` requirement — is itself `async`.
final class ManualClock: Clock, Sendable {
    typealias Duration = Swift.Duration

    /// The state the mutex guards.
    private struct State {
        /// The current virtual instant.
        var currentInstant = ManualInstant(offset: .zero)

        /// Every requested sleep, in call order.
        var sleeps: [Swift.Duration] = []
    }

    /// The guarded state.
    private let state = Mutex(State())

    /// Every duration requested through `sleep(until:tolerance:)`, in call
    /// order — the backoff schedule a test asserts against.
    var recordedSleeps: [Swift.Duration] {
        state.withLock { $0.sleeps }
    }

    /// The current virtual instant, advanced only by
    /// ``sleep(until:tolerance:)``.
    var now: ManualInstant {
        state.withLock { $0.currentInstant }
    }

    /// No meaningful minimum resolution: a manual clock has no real
    /// scheduling granularity.
    var minimumResolution: Swift.Duration { .zero }

    /// Records the requested delay and advances ``now`` to `deadline`,
    /// without a real suspension.
    ///
    /// - Parameters:
    ///   - deadline: The instant to "sleep" until.
    ///   - tolerance: Ignored — a manual clock has no scheduling jitter.
    func sleep(until deadline: ManualInstant, tolerance: Swift.Duration?) async throws {
        state.withLock { current in
            current.sleeps.append(current.currentInstant.duration(to: deadline))
            if deadline > current.currentInstant {
                current.currentInstant = deadline
            }
        }
    }
}
