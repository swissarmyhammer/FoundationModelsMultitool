import Foundation
import Testing

// MARK: - The one poll of this test target
//
// Some readings a test takes become true a little AFTER the call that makes
// them true: a background run reaches the run plane after the call that parked it
// answered, a gated call starts after the snippet that called it returned, a
// process group goes away after the sweep that killed it returned, a registry
// drains after the teardown that started it.
//
// A read taken at that instant is a race, and a fixed sleep is slack. A poll is
// neither: it re-reads until the reading holds, and it gives up at a deadline
// that bounds a genuine hang. One poll stands here, thus every suite that takes
// one reads the same loop, the same interval and the same deadline, and no copy
// can drift from another.

/// The poll a test takes while it waits for a reading to become true.
enum TestPoll {

    /// How many milliseconds a poll waits between reads.
    private static let intervalMilliseconds = 25

    /// How long a poll waits between reads.
    static let interval = Duration.milliseconds(intervalMilliseconds)

    /// How many seconds a poll keeps reading before it gives up.
    private static let deadlineSeconds = 10

    /// How long a poll keeps reading before it gives up.
    ///
    /// A poll is a synchronization point and never a timing assertion, thus
    /// this bounds a genuine hang and states nothing about how quickly the
    /// reading becomes true.
    static let deadline = Duration.seconds(deadlineSeconds)

    /// What ``waitUntil(_:before:_:)`` calls a condition its caller did not
    /// name.
    private static let unnamedCondition = "the condition"

    /// Polls `condition` until it holds, or until `deadline` passes.
    ///
    /// The answer is a reading and never a failure, thus a caller that wants
    /// its own message states one — `#expect(held, "…")`. A caller that wants
    /// the failure itself takes ``waitUntil(_:before:_:)``.
    ///
    /// - Parameters:
    ///   - deadline: How long to keep reading.
    ///   - condition: The reading to take.
    /// - Returns: `true` when the condition held before the deadline.
    static func holds(
        before deadline: Duration = TestPoll.deadline, _ condition: () async -> Bool
    ) async -> Bool {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end {
            if await condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return await condition()
    }

    /// Polls `condition` until it holds, and fails the test when it never does.
    ///
    /// - Parameters:
    ///   - description: What the test waited to observe, which the failure
    ///     names.
    ///   - deadline: How long to keep reading.
    ///   - condition: The reading to take.
    /// - Throws: ``ConditionNeverHeld`` when the deadline passes first, after
    ///   the failure is recorded.
    static func waitUntil(
        _ description: String = unnamedCondition,
        before deadline: Duration = TestPoll.deadline,
        _ condition: () async -> Bool
    ) async throws {
        guard await holds(before: deadline, condition) else {
            Issue.record("\(description) never held within \(deadline)")
            throw ConditionNeverHeld()
        }
    }

    /// The failure ``waitUntil(_:before:_:)`` throws when the deadline passes
    /// before the condition holds.
    ///
    /// Always thrown after that call has recorded the `Issue` naming what the
    /// test waited for.
    struct ConditionNeverHeld: Error {}
}
