import Foundation

/// A one-way gate a slow fixture tool is held behind until the scenario driving
/// it says the tool may finish.
///
/// **Why a gated fixture rather than a long `Task.sleep`.** The in-band
/// collection canary asks when the model's `runCode` run left the run plane
/// relative to the end of its turn, and that has to be a fact rather than a
/// coincidence. A fixture that sleeps for a fixed span makes it a race between a
/// sleep and a live 30B model's decode speed, and losing the race does not fail
/// loudly — it produces exactly the reading the canary exists to watch for,
/// while meaning nothing. A gate removes the race: the run cannot leave the run
/// plane early, because the fixture behind the gate is not free to return.
///
/// **The ceiling is what ends the wait on an ordinary run, not an exception.**
/// `waitUntilOpen(orAfter:)` gives up after a bound because the gate is normally
/// never opened in time: the model answers its pending envelope by calling
/// `wait`, and that call blocks the turn until the run settles, the run cannot
/// settle until the gate opens, and the gate opens on the turn ending. Router's
/// `^466d38p` says every park carries the instruction that produces that `wait`,
/// so this is the path a passing canary run takes. Without the ceiling the
/// scenario would deadlock on every run and be killed by the suite's time limit
/// having said nothing; with it, the fixture reports, the model collects, and the
/// canary reads an empty plane at the turn's end — which is the observation it
/// grades.
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
    /// ``pollInterval`` stated as a count of milliseconds.
    ///
    /// 50 ms is short enough that the wait it adds is lost in a live turn's own
    /// decode time — a turn takes tens of seconds, so at worst one poll of
    /// latency is under a thousandth of it — and long enough that a wait as long
    /// as ``IntegrationArchiveRebuildTool``'s whole ceiling is a couple of
    /// thousand actor hops rather than a spin.
    ///
    /// A separate constant from ``pollInterval`` because `Duration` has no
    /// literal form: the number has to be named somewhere, and naming it here
    /// keeps the unit in the name beside the value.
    private static let pollIntervalMilliseconds = 50

    /// How long a waiter sleeps between reads of ``isOpen``.
    static let pollInterval: Duration = .milliseconds(pollIntervalMilliseconds)

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
