import Foundation

@testable import MultitoolTestSupport

// MARK: - The poll values of this gated target
//
// Some readings a gated scenario takes become true a little AFTER the call that
// makes them true, and a live model decides WHEN that call happens. A shell run
// reaches the run plane when the engine tracks it, a child registers its process
// group inside the spawn, and a process group goes away after the canceler that
// killed it returned.
//
// The loop is `TestPoll`, the one poll of the test support code. It stands in
// the `MultitoolTestSupport` product of the root package, thus this target
// takes it from there and does not write the loop again. This file holds only
// the values of this target: `TestPoll` reads every 25 milliseconds and gives
// up after the hang guard of a unit test. One live-model turn takes minutes,
// thus this target reads less frequently and gives up after a hang guard of
// its own.

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

    /// How many minutes a poll keeps reading before it gives up: twenty.
    private static let deadlineMinutes = 20

    /// How long a poll keeps reading before it gives up. Every poll of this
    /// target takes this one value.
    ///
    /// This is a hang guard, and not a speed check. No test checks the speed
    /// of the machine (decision of the user, cards `^tm4x2hp` and
    /// `^kdtrmhv`). A poll is a synchronization point, thus this bounds a
    /// genuine hang and states nothing about how quickly the reading becomes
    /// true. The value is far above the slowest step seen on a busy machine
    /// (one model turn of 362 s, a model load of 359 s), and below
    /// ``IntegrationHangGuard/timeLimit``, thus a poll that never holds
    /// reports what it read before the time limit of its test stops it.
    static let deadline = Duration.seconds(deadlineMinutes * secondsPerMinute)

    /// The seconds in one minute, for ``deadline``.
    private static let secondsPerMinute = 60

    /// Polls `condition` until it holds, or until ``deadline`` passes.
    ///
    /// The answer is a reading and never a failure: a gated scenario collects
    /// every reading it took and grades them together, so a poll that gave up
    /// reports that and lets the verdict say what it means.
    ///
    /// - Parameter condition: The reading to take.
    /// - Returns: `true` when the condition held before the deadline.
    static func holds(_ condition: () async -> Bool) async -> Bool {
        await TestPoll.holds(before: deadline, every: interval, condition)
    }
}
