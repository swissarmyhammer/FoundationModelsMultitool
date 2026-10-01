// `TestHangGuard` — the one `.timeLimit` of the unit tests.
//
// No test checks the speed of the machine (decision of the user, card
// `^tm4x2hp`). A time check in a test uses an injected clock or an event. A
// `.timeLimit` is a hang guard only: it stops a test that can never end, and
// it must not fail a test that makes progress on a busy machine.

import Testing

/// The hang guard of a unit test that can hang when the code under test is
/// wrong.
enum TestHangGuard {
    /// How many minutes a guarded unit test can run before the guard stops it.
    ///
    /// A unit test step takes seconds, also on a busy machine. Ten minutes is
    /// far above that, and above ``TestPoll/deadline``, thus a poll that never
    /// holds reports its own failure first.
    private static let minutes = 10

    /// The `.timeLimit` of a guarded unit test.
    ///
    /// This is a hang guard, and not a speed check.
    static let timeLimit = TimeLimitTrait.Duration.minutes(minutes)
}
