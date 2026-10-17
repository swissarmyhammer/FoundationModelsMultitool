// `EventRace` — the one wait of the unit suites that ends on the first of two
// events.
//
// Test rule T1: each wait of a test must also end on the failure event, or
// the test must fail before it waits. A test that waits only for the event it
// expects hangs when that event does not come. Thus a test waits here for the
// first of two events: the event it expects, or an event that shows that the
// expected event cannot come any more — for example the end of the call that
// must make the expected event occur. Each of the two events can occur, thus
// the wait always ends, and the caller then checks which event came.
//
// No time is in this file. No clock, no sleep and no poll ends a wait.

/// The waits that end on the first of two events.
enum EventRace {
    /// Waits for the first event: `expected` returned, or one of `others`
    /// returned. Then this function cancels each wait and waits until each
    /// of them ended, thus no wait stays open after it returns.
    ///
    /// This function does not know which event came: the caller checks it,
    /// and fails at once when the expected event did not come.
    ///
    /// - Parameters:
    ///   - expected: The wait for the event that the test expects. A cancel
    ///     must end it.
    ///   - others: The waits for the events that show that the expected
    ///     event cannot come any more. A cancel must end each of them.
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   first event.
    static func firstOf(
        _ expected: @escaping @Sendable () async -> Void,
        or others: (@Sendable () async -> Void)...
    ) async throws {
        let firstEvent = TestGate()
        let waits = ([expected] + others).map { wait in
            Task {
                await wait()
                firstEvent.open()
            }
        }
        do {
            try await firstEvent.wait()
        } catch {
            await endWaits(waits)
            throw error
        }
        await endWaits(waits)
    }

    /// Work that a test started, and the gate that the end of the work opens.
    ///
    /// The end of the work is the second event of each wait of the test for
    /// a step of that work: a work that ended cannot do its step any more.
    struct Watched<Success: Sendable>: Sendable {
        /// The task of the work.
        let task: Task<Success, any Error>

        /// The gate that opens when the work ended, with a result or with an
        /// error.
        let ended: TestGate

        /// Waits until the work ended. A cancel of the task of the caller
        /// also ends the wait, thus ``EventRace/firstOf(_:or:)`` can end it.
        func waitForEnd() async {
            try? await ended.wait()
        }
    }

    /// Starts `work`, and gives the test its task and the gate of its end.
    ///
    /// - Parameter work: The work to start.
    /// - Returns: The started work.
    static func watch<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success
    ) -> Watched<Success> {
        let ended = TestGate()
        let task = Task {
            defer { ended.open() }
            return try await work()
        }
        return Watched(task: task, ended: ended)
    }

    /// Starts `work`, and waits for its event — the one wait of a test that
    /// starts work and then waits until the work did its step.
    ///
    /// The wait ends on the first of two events: `arrival` returned, or
    /// `work` ended — see ``firstOf(_:or:)``. When the wait throws,
    /// `cleanUp` gets the task of `work` before the throw. This function
    /// does not know if the event came: the caller checks it, and fails at
    /// once when it did not come.
    ///
    /// - Parameters:
    ///   - work: The work that makes the event occur.
    ///   - arrival: The wait for the event. A cancel must end it.
    ///   - cleanUp: Ends `work` when the wait throws. The default does
    ///     nothing: the teardown of the test then ends `work`.
    /// - Returns: The task of `work`.
    /// - Throws: When the task is cancelled before the first event.
    static func start<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success,
        awaiting arrival: @escaping @Sendable () async -> Void,
        cleaningUpOnThrow cleanUp: (Task<Success, any Error>) async -> Void = { _ in }
    ) async throws -> Task<Success, any Error> {
        let watched = watch(work)
        do {
            try await firstOf(arrival, or: { await watched.waitForEnd() })
        } catch {
            await cleanUp(watched.task)
            throw error
        }
        return watched.task
    }

    /// Cancels `wait`, and waits until it ended — the one cancel-then-await
    /// teardown of a wait. A cancel ends each wait that ``firstOf(_:or:)``
    /// gets, and each wait that a test gives to it as its work, thus this
    /// call always returns.
    ///
    /// - Parameter wait: The task of a wait that a cancel ends.
    static func endWait<Success: Sendable, Failure: Error>(_ wait: Task<Success, Failure>) async {
        wait.cancel()
        _ = await wait.result
    }

    /// Cancels each of `waits`, and waits until each of them ended.
    ///
    /// - Parameter waits: The tasks of the waits of ``firstOf(_:or:)``.
    private static func endWaits(_ waits: [Task<Void, Never>]) async {
        for wait in waits {
            await endWait(wait)
        }
    }
}
