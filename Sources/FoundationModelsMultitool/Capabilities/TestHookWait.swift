// `TestHookWait` — the one cancel scaffold of the waits of the internal test
// hooks of this package, and of `MCPServer.waitUntilReady()`.
//
// Some actors give a test an internal hook that waits for one event of the
// actor, in place of a poll: `MCPServer` (for example
// `waitUntilTransportDropped()`) and `ShellState` (for example
// `waitForStoredLines(commandID:atLeast:)`). A cancel of the task of the test
// must end each such wait, also a cancel that came before the call. Thus no
// continuation stays open when the test stops its wait. Each hook formerly
// held its own copy of the steps that do this. This file holds the single
// implementation, thus the copies cannot drift apart when the cancel rules
// change.
//
// One product wait uses the same steps: `MCPServer.waitUntilReady()`. A cancel
// of its caller must end it too, and a second copy of the steps would drift.

/// The cancel scaffold that the waits of the internal test hooks share.
///
/// The callers are internal hooks for `@testable import`, and one product
/// wait: `MCPServer.waitUntilReady()`.
enum TestHookWait {
    /// Suspends until one wait of a test hook of `owner` ends, and gives the
    /// value that ended it.
    ///
    /// The steps, in order:
    ///
    /// 1. A cancel that came before the call returns `cancelValue` at once.
    /// 2. Else, when `resolvedValue` gives a value, the wait has nothing to
    ///    wait for and returns that value at once.
    /// 3. Else `record` records the continuation of the wait in the store of
    ///    the hook. A resume of that store ends the wait. A cancel of the
    ///    calling task calls `end` on `owner` with `cancelValue`.
    ///
    /// The check of the cancel and the record of the wait occur in one hop of
    /// `owner`. A cancel that comes after the check sends its `end` in a
    /// later hop of `owner`, thus that `end` finds the recorded wait.
    ///
    /// - Parameters:
    ///   - owner: The actor that holds the store of the hook.
    ///   - cancelValue: The value the wait gives when a cancel ends it.
    ///   - resolvedValue: Gives the value of a wait that has nothing to wait
    ///     for, or `nil` when the wait must suspend.
    ///   - record: Records the continuation of the wait.
    ///   - end: Ends the recorded wait with the value it gets — the cancel
    ///     step. It runs on `owner`, and does nothing when the wait ended
    ///     before.
    /// - Returns: The value that ended the wait.
    static func suspend<Owner: Actor, WaitValue: Sendable>(
        on owner: isolated Owner,
        cancelValue: WaitValue,
        resolvedValue: () -> WaitValue?,
        record: (CheckedContinuation<WaitValue, Never>) -> Void,
        end: @escaping @Sendable (isolated Owner, WaitValue) -> Void
    ) async -> WaitValue {
        guard !Task.isCancelled else { return cancelValue }
        if let resolved = resolvedValue() { return resolved }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in record(continuation) }
        } onCancel: {
            Task { await end(owner, cancelValue) }
        }
    }

    /// Suspends until one wait of the store `store` of `owner` ends, and
    /// gives the value that ended it — the steps of
    /// ``suspend(on:cancelValue:resolvedValue:record:end:)`` for a wait that
    /// a ``TestHookWaiters`` store holds.
    ///
    /// The wait gets a wait id from the store. The record step records the
    /// continuation under that id with `detail`, and then calls `didRecord`.
    /// The cancel step ends the wait of that id in the store.
    ///
    /// Swift 6 cannot form a key path to an actor-isolated property, thus the
    /// store goes in as a closure that gives in-out access to it on `owner`.
    ///
    /// - Parameters:
    ///   - owner: The actor that holds the store of the hook.
    ///   - store: Calls its second argument with in-out access to the store
    ///     of the hook on the given owner.
    ///   - detail: The detail that the wait waits for.
    ///   - cancelValue: The value the wait gives when a cancel ends it.
    ///   - resolvedValue: Gives the value of a wait that has nothing to wait
    ///     for, or `nil` when the wait must suspend.
    ///   - didRecord: Runs on `owner` after the record of the wait.
    /// - Returns: The value that ended the wait.
    static func suspend<Owner: Actor, WaitValue: Sendable, Detail: Sendable>(
        on owner: isolated Owner,
        in store: @escaping TestHookWaiterStore<Owner, WaitValue, Detail>,
        detail: Detail,
        cancelValue: WaitValue,
        resolvedValue: () -> WaitValue?,
        didRecord: () -> Void = {}
    ) async -> WaitValue {
        var newWaiterID = 0
        store(owner) { newWaiterID = $0.makeWaiterID() }
        let waiterID = newWaiterID
        return await suspend(
            on: owner,
            cancelValue: cancelValue,
            resolvedValue: resolvedValue,
            record: { continuation in
                store(owner) { $0.record(continuation, as: waiterID, detail: detail) }
                didRecord()
            },
            end: { owner, value in store(owner) { $0.end(waiterID, with: value) } })
    }
}

/// The in-out access to one ``TestHookWaiters`` store of `Owner`: calls its
/// second argument with the store of the given owner.
typealias TestHookWaiterStore<Owner: Actor, WaitValue: Sendable, Detail: Sendable> =
    @Sendable (isolated Owner, (inout TestHookWaiters<WaitValue, Detail>) -> Void) -> Void
