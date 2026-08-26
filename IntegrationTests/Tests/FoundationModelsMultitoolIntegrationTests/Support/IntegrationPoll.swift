import Foundation

// MARK: - The one poll of this gated target
//
// Some readings a gated scenario takes become true a little AFTER the call that
// makes them true, and a live model decides WHEN that call happens. A shell run
// reaches the run plane when the engine tracks it, a child registers its process
// group inside the spawn, and a process group goes away after the canceler that
// killed it returned.
//
// A read taken at one instant is a race, and a fixed sleep is slack. A poll is
// neither: it re-reads until the reading holds, and it gives up at a deadline
// that bounds a genuine hang.
//
// **This is not `TestPoll`, and it cannot be.** `TestPoll` stands in
// `Tests/FoundationModelsMultitoolTests/Fixtures/PollFixtures.swift`, which
// belongs to the root package's test target. A nested package cannot import
// another package's test target, so the loop is written again here rather than
// shared. The deadlines are this target's own in any case: `TestPoll` waits ten
// seconds, which bounds a unit test's hang and is far under the minutes one
// live-model turn takes.

/// The poll a gated scenario takes while it waits for a reading to become true.
enum IntegrationPoll {

    /// How many milliseconds a poll waits between reads.
    private static let intervalMilliseconds = 250

    /// How long a poll waits between reads.
    ///
    /// Ten times `TestPoll`'s interval: nothing here is read thousands of times,
    /// and a quarter of a second keeps the loop free beside a turn that runs for
    /// minutes.
    static let interval = Duration.milliseconds(intervalMilliseconds)

    /// How many seconds a poll keeps reading before it gives up, when its caller
    /// names no deadline of its own.
    private static let deadlineSeconds = 60

    /// How long a poll keeps reading before it gives up.
    ///
    /// A poll is a synchronization point and never a timing assertion, thus this
    /// bounds a genuine hang and states nothing about how quickly the reading
    /// becomes true.
    static let deadline = Duration.seconds(deadlineSeconds)

    /// Polls `condition` until it holds, or until `deadline` passes.
    ///
    /// The answer is a reading and never a failure: a gated scenario collects
    /// every reading it took and grades them together, so a poll that gave up
    /// reports that and lets the verdict say what it means.
    ///
    /// - Parameters:
    ///   - deadline: How long to keep reading.
    ///   - condition: The reading to take.
    /// - Returns: `true` when the condition held before the deadline.
    static func holds(
        before deadline: Duration = IntegrationPoll.deadline, _ condition: () async -> Bool
    ) async -> Bool {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end {
            if await condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return await condition()
    }
}
