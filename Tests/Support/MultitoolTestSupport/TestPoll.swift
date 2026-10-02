// `TestPoll` — the one poll of the test support code.
//
// Some readings a test takes become true a little AFTER the call that makes
// them true: a background run reaches the run plane after the call that
// started it answered, a gated call starts after the snippet that called it
// returned, a process group goes away after the sweep that killed it returned,
// a registry drains after the teardown that started it, a child process exits
// after the signal that stops it.
//
// A read taken at that instant is a race, and a fixed sleep is slack. A poll is
// neither: it re-reads until the reading holds, and it gives up at a deadline
// that bounds a genuine hang. One poll stands here, thus every suite that takes
// one reads the same loop, and no copy can drift from another.
//
// The poll stands in the `MultitoolTestSupport` product and not in one test
// target, because the unit test target and the nested `IntegrationTests`
// package both take it, and a package imports the products of another package
// only. A caller that needs a different interval or deadline gives its own
// value as an argument, and does not write the loop again.

import Foundation
import Testing

/// The poll a test takes while it waits for a reading to become true.
enum TestPoll {

    /// How many milliseconds a poll waits between reads.
    private static let intervalMilliseconds = 25

    /// How long a poll waits between reads, when its caller names no interval
    /// of its own.
    static let interval = Duration.milliseconds(intervalMilliseconds)

    /// How many seconds a poll keeps reading before it gives up: five minutes.
    private static let deadlineSeconds = 300

    /// How long a poll keeps reading before it gives up, when its caller names
    /// no deadline of its own.
    ///
    /// This is a hang guard, and not a speed check. No test checks the speed
    /// of the machine (decision of the user, card `^tm4x2hp`). A poll is a
    /// synchronization point, thus this bounds a genuine hang and states
    /// nothing about how quickly the reading becomes true. The value is far
    /// above the time that a step of a unit test takes on a busy machine, and
    /// below ``TestHangGuard/timeLimit``, thus a poll that never holds reports
    /// its own named failure before the time limit of its test stops it.
    static let deadline = Duration.seconds(deadlineSeconds)

    /// What ``waitUntil(_:before:every:_:)`` calls a condition its caller did
    /// not name.
    private static let unnamedCondition = "the condition"

    /// Polls `condition` until it holds, or until `deadline` passes.
    ///
    /// The answer is a reading and never a failure, thus a caller that wants
    /// its own message states one — `#expect(held, "…")`. A caller that wants
    /// the failure itself takes ``waitUntil(_:before:every:_:)``.
    ///
    /// - Parameters:
    ///   - deadline: How long to keep reading.
    ///   - interval: How long to wait between two reads.
    ///   - condition: The reading to take.
    /// - Returns: `true` when the condition held before the deadline.
    static func holds(
        before deadline: Duration = TestPoll.deadline,
        every interval: Duration = TestPoll.interval,
        _ condition: () async -> Bool
    ) async -> Bool {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end {
            if await condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return await condition()
    }

    /// Reads `read` until its reading satisfies `isReady`, or until
    /// `deadline` passes, and answers the last reading.
    ///
    /// The answer is a reading and never a failure, thus the caller states
    /// its own expectation on it. A read that throws ends the poll, and the
    /// error goes on to the caller.
    ///
    /// - Parameters:
    ///   - deadline: How long to keep reading.
    ///   - interval: How long to wait between two reads.
    ///   - read: The reading to take.
    ///   - isReady: What the reading must satisfy.
    /// - Returns: The last reading the poll took.
    /// - Throws: What `read` throws.
    static func lastReading<Reading>(
        before deadline: Duration = TestPoll.deadline,
        every interval: Duration = TestPoll.interval,
        of read: () async throws -> Reading,
        until isReady: (Reading) -> Bool
    ) async rethrows -> Reading {
        let end = ContinuousClock.now + deadline
        var reading = try await read()
        while !isReady(reading), ContinuousClock.now < end {
            try? await Task.sleep(for: interval)
            reading = try await read()
        }
        return reading
    }

    /// Polls `condition` until it holds, and fails the test when it never does.
    ///
    /// - Parameters:
    ///   - description: What the test waited to observe, which the failure
    ///     names.
    ///   - deadline: How long to keep reading.
    ///   - interval: How long to wait between two reads.
    ///   - condition: The reading to take.
    /// - Throws: ``ConditionNeverHeld`` when the deadline passes first, after
    ///   the failure is recorded.
    static func waitUntil(
        _ description: String = unnamedCondition,
        before deadline: Duration = TestPoll.deadline,
        every interval: Duration = TestPoll.interval,
        _ condition: () async -> Bool
    ) async throws {
        guard await holds(before: deadline, every: interval, condition) else {
            Issue.record("\(description) never held within \(deadline)")
            throw ConditionNeverHeld()
        }
    }

    /// The failure ``waitUntil(_:before:every:_:)`` throws when the deadline
    /// passes before the condition holds.
    ///
    /// Always thrown after that call has recorded the `Issue` naming what the
    /// test waited for.
    struct ConditionNeverHeld: Error {}
}
