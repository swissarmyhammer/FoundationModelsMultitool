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

import Testing

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
        try await firstOf(expected, orAnyOf: others)
    }

    /// Waits for the first of the events, and then fails the test at once
    /// unless `gate` is open — the one race-and-require step of a test that
    /// waits for a gate.
    ///
    /// The wait ends on the first event: `gate` opened, or one of `others`
    /// returned — see ``firstOf(_:or:)``.
    ///
    /// - Parameters:
    ///   - gate: The gate that the expected event opens.
    ///   - others: The waits for the events that show that the expected
    ///     event cannot come any more. A cancel must end each of them.
    ///   - failure: What the failure of the test says when `gate` is not
    ///     open.
    ///   - sourceLocation: The place in the test that the failure names.
    /// - Throws: When `gate` is not open, or when the task is cancelled
    ///   before the first event.
    static func requireOpen(
        _ gate: TestGate,
        orFirstOf others: (@Sendable () async -> Void)...,
        orFail failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await require(
            { try? await gate.wait() }, orAnyOf: others, requiring: { gate.isOpen }, orFail: failure,
            sourceLocation: sourceLocation)
    }

    /// Waits for the first event: `expected` returned, or one of `others`
    /// returned — the body of ``firstOf(_:or:)``.
    ///
    /// - Parameters:
    ///   - expected: The wait for the event that the test expects. A cancel
    ///     must end it.
    ///   - others: The waits for the events that show that the expected
    ///     event cannot come any more. A cancel must end each of them.
    /// - Throws: `CancellationError` when the task is cancelled before the
    ///   first event.
    private static func firstOf(
        _ expected: @escaping @Sendable () async -> Void,
        orAnyOf others: [@Sendable () async -> Void]
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

    /// Starts `work`, waits for its event, and then fails the test at once
    /// unless the event came — the one start-and-require step of a test.
    ///
    /// The wait ends on the first of two events: `arrival` returned, or
    /// `work` ended — see ``firstOf(_:or:)``. When the wait throws, the
    /// teardown of the test ends `work`.
    ///
    /// - Parameters:
    ///   - work: The work that makes the event occur.
    ///   - arrival: The wait for the event. A cancel must end it.
    ///   - hasArrived: Whether the event came.
    ///   - failure: What the failure of the test says when the event did
    ///     not come.
    ///   - sourceLocation: The place in the test that the failure names.
    /// - Returns: The started work.
    /// - Throws: When the event did not come, or when the task is cancelled
    ///   before the first event.
    static func watch<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success,
        awaiting arrival: @escaping @Sendable () async -> Void,
        requiring hasArrived: () -> Bool,
        orFail failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Watched<Success> {
        let watched = watch(work)
        try await require(
            arrival, orAnyOf: [{ await watched.waitForEnd() }], requiring: hasArrived, orFail: failure,
            sourceLocation: sourceLocation)
        return watched
    }

    /// Starts `work`, waits until `gate` opened, and then fails the test at
    /// once unless `gate` is open — see
    /// ``watch(_:awaiting:requiring:orFail:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - work: The work that opens `gate`.
    ///   - gate: The gate that the event of `work` opens.
    ///   - failure: What the failure of the test says when `gate` is not
    ///     open.
    ///   - sourceLocation: The place in the test that the failure names.
    /// - Returns: The started work.
    /// - Throws: When `gate` is not open, or when the task is cancelled
    ///   before the first event.
    static func watch<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success,
        untilOpen gate: TestGate,
        orFail failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Watched<Success> {
        try await watch(
            work, awaiting: { try? await gate.wait() }, requiring: { gate.isOpen }, orFail: failure,
            sourceLocation: sourceLocation)
    }

    /// Starts `work`, waits until its call arrived at `held`, and then fails
    /// the test at once unless the call arrived — see
    /// ``watch(_:awaiting:requiring:orFail:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - work: The work that calls `held`.
    ///   - held: The held tool that the call of `work` arrives at.
    ///   - failure: What the failure of the test says when no call arrived.
    ///   - sourceLocation: The place in the test that the failure names.
    /// - Returns: The started work.
    /// - Throws: When no call arrived, or when the task is cancelled before
    ///   the first event.
    static func watch<Success: Sendable>(
        _ work: @escaping @Sendable () async throws -> Success,
        untilArrivalAt held: HeldScriptedTool,
        orFail failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Watched<Success> {
        try await watch(
            work, awaiting: { try? await held.waitForArrival() }, requiring: { held.hasArrived },
            orFail: failure, sourceLocation: sourceLocation)
    }

    /// Waits for the first of the events, and then fails the test at once
    /// unless `hasArrived` is true — the body of each race-and-require step.
    ///
    /// - Parameters:
    ///   - expected: The wait for the event that the test expects. A cancel
    ///     must end it.
    ///   - others: The waits for the events that show that the expected
    ///     event cannot come any more. A cancel must end each of them.
    ///   - hasArrived: Whether the expected event came.
    ///   - failure: What the failure of the test says when the event did
    ///     not come.
    ///   - sourceLocation: The place in the test that the failure names.
    /// - Throws: When the event did not come, or when the task is cancelled
    ///   before the first event.
    private static func require(
        _ expected: @escaping @Sendable () async -> Void,
        orAnyOf others: [@Sendable () async -> Void],
        requiring hasArrived: () -> Bool,
        orFail failure: Comment,
        sourceLocation: SourceLocation
    ) async throws {
        try await firstOf(expected, orAnyOf: others)
        try #require(hasArrived(), failure, sourceLocation: sourceLocation)
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
