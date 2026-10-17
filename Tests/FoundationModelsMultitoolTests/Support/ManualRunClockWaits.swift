// `ManualRunClock` waits that end on the first of two events, and on a
// cancel.
//
// `ManualRunClock.waitForSleepers(atLeast:)` stands in the package
// FoundationModelsExtras, and it has no cancellation handler: a cancel of
// its task does not end it, and a count of waits that never comes makes it
// wait for ever. This target does not change that package. The wait below
// runs that wait in a task of its own, and the caller waits on a `TestGate`
// in its place. The gate opens on the first of two events: the count of
// waits came, or the second event of the caller came. A cancel of the task
// of the caller ends the wait on the gate.
//
// The wait of the package stays open until the clock gets the count of
// waits, because no cancel can end it. It holds no lock and no test
// resource: it is one parked task. The change that ends it on a cancel is a
// change of FoundationModelsExtras.

import FoundationModelsExtras

extension ManualRunClock {
    /// Waits until at least `count` waits are open on this clock, or until
    /// `ended` ends first, or until the task of the caller is cancelled.
    ///
    /// A clock that never gets the waits then does not hang the test: the
    /// caller goes on, and its check of the answer of the call fails.
    ///
    /// - Parameters:
    ///   - count: The number of waits.
    ///   - ended: The wait for the event that shows that no wait comes, for
    ///     example the end of the call that must put the waits on the clock.
    func waitForSleepers(atLeast count: Int, orUntil ended: @escaping @Sendable () async -> Void) async {
        let firstEvent = TestGate()
        let sleepers = Task {
            await self.waitForSleepers(atLeast: count)
            firstEvent.open()
        }
        let end = Task {
            await ended()
            firstEvent.open()
        }
        // A cancel ends the wait: the caller goes on, and its cancelled task
        // ends the work after the wait.
        try? await firstEvent.wait()
        end.cancel()
        sleepers.cancel()
    }
}
