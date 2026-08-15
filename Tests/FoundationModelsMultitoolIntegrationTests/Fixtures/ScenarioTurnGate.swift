import Foundation

/// A one-way gate a slow fixture tool is held behind until the scenario driving
/// it says the tool may finish.
///
/// **Why a gated fixture rather than a long `Task.sleep`.** The parked-run drain
/// scenario needs one fact to be true and not merely likely: the model's turn
/// must end while its `runCode` run is *still parked*. A fixture that sleeps for
/// a fixed span makes that a race between a sleep and a live 30B model's decode
/// speed, and losing the race does not fail loudly — the run settles early, the
/// run plane is empty when `respond`'s drain snapshots it, no continuation turn
/// runs at all, and the scenario fails for a reason that looks nothing like the
/// timing that caused it. A gate removes the race: the run cannot leave the run
/// plane until the scenario has already seen the turn end.
///
/// **The ceiling is not a second timing assumption.** `waitUntilOpen(orAfter:)`
/// gives up after a bound because there is one way the gate is never opened: a
/// model that answers its pending envelope by calling `wait`. That call blocks
/// the turn until the run settles, the run cannot settle until the turn ends,
/// and the turn cannot end until the call returns. The ceiling breaks that
/// deadlock so the scenario fails on its own `waitCalls == 0` assertion — the
/// honest reading of what happened — instead of hanging until the suite's time
/// limit kills it and says nothing.
///
/// **Polled rather than continuation-based.** A waiter parked on a
/// `CheckedContinuation` and raced against a deadline needs the machinery
/// Router's own `RaceGate` exists for: a task group awaits every child, so the
/// abandoned wait would still hold the caller, and a continuation is not
/// cancellation-aware. This fixture only has to notice a flag flip, and paying
/// ``pollInterval`` to notice it costs a gated scenario nothing measurable.
///
/// An `actor` because the scenario opens the gate from its own task while the
/// fixture tool reads it from the run's task.
actor ScenarioTurnGate {
    /// How long a waiter sleeps between reads of ``isOpen``.
    ///
    /// Short enough that the wait it adds is lost in a live turn's own decode
    /// time, long enough that a minutes-long wait is a few thousand actor hops
    /// rather than a spin.
    static let pollInterval: Duration = .milliseconds(50)

    /// Whether the gate has been opened.
    private(set) var isOpen = false

    /// Opens the gate, releasing every waiter at its next poll.
    ///
    /// Idempotent: the scenario opens the gate on the first turn that ends and
    /// again on the way out, and a gate is never closed again.
    func open() {
        isOpen = true
    }

    /// Waits until the gate opens, until `ceiling` elapses, or until the calling
    /// task is cancelled — whichever comes first.
    ///
    /// Returns rather than throwing on every one of the three, because a fixture
    /// tool that threw here would be recorded as an invocation that did not
    /// return, and the scenario reading that record would report a fixture
    /// failure where the real fact is that the gate never opened.
    ///
    /// - Parameter ceiling: the longest this waits for an unopened gate.
    nonisolated func waitUntilOpen(orAfter ceiling: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: ceiling)
        while ContinuousClock.now < deadline {
            if await isOpen { return }
            if Task.isCancelled { return }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}
