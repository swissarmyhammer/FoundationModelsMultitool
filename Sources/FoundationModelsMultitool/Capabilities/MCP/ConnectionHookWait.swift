// `ConnectionHookWait` — how a wait of a connection test hook of `MCPServer`
// ends.
//
// Two internal test hooks of `MCPServer` wait for an event of the connection:
// `waitUntilTransportDropped()` and `waitUntilToolListChangedGeneration(reaches:)`.
// Test rule T1: each wait must also end when the event cannot come any more.
// When the connection ends, the event of the wait cannot come on that
// connection, thus the end of the connection also ends the wait. The hook then
// throws ``ConnectionHookWaitError/connectionEnded``, and the test fails at
// once with that reason.

/// How one wait of a connection test hook of `MCPServer` ended.
enum ConnectionHookWaitEnd: Sendable {
    /// The event that the wait waits for came.
    case event

    /// A cancel of the task of the wait ended it.
    case cancelled

    /// The connection ended before the event came.
    case connectionEnded

    /// Throws when the connection ended before the event came.
    ///
    /// - Throws: ``ConnectionHookWaitError/connectionEnded`` for
    ///   ``connectionEnded``.
    func throwIfConnectionEnded() throws {
        guard self != .connectionEnded else { throw ConnectionHookWaitError.connectionEnded }
    }
}

/// The error that a connection test hook of `MCPServer` throws when the
/// connection ended before the event of the wait came.
enum ConnectionHookWaitError: Error, Equatable {
    /// The connection ended before the event came: for example a
    /// `disconnect()`, a new connect, or a transport drop.
    case connectionEnded
}

extension MCPServer {
    /// Waits until a wait of ``waitUntilTransportDropped()`` or of
    /// ``waitUntilToolListChangedGeneration(reaches:)`` is recorded — the
    /// event a test waits on before it makes the event that must end that
    /// wait. Returns at once when such a wait is recorded already. A cancel
    /// of the calling task ends the wait, also a cancel that came before the
    /// call.
    ///
    /// Internal, for `@testable import`: no product code waits here.
    func waitUntilConnectionHookWaitIsRecorded() async {
        await TestHookWait.suspend(
            on: self,
            in: { server, access in access(&server.connectionHookWaitRecordedWaiters) },
            detail: (),
            cancelValue: (),
            resolvedValue: { hasRecordedConnectionHookWait ? () : nil })
    }

    /// Suspends one wait of a connection test hook until its event comes, and
    /// throws when the connection ends first — the steps that
    /// ``waitUntilTransportDropped()`` and
    /// ``waitUntilToolListChangedGeneration(reaches:)`` share.
    ///
    /// The steps, in order:
    ///
    /// 1. When `eventCame` is `true`, the wait returns at once.
    /// 2. Else, when `connectionEnded` is `true`, the wait throws at once.
    /// 3. Else the wait records itself in `store` with `detail`, and resumes
    ///    each wait of ``waitUntilConnectionHookWaitIsRecorded()``. A cancel
    ///    of the calling task ends the wait with no throw.
    ///
    /// - Parameters:
    ///   - eventCame: Whether the event of the wait came before the call.
    ///   - connectionEnded: Whether the connection ended before the call.
    ///   - store: The in-out access to the store of the hook.
    ///   - detail: The detail that the wait waits for.
    /// - Throws: ``ConnectionHookWaitError/connectionEnded`` when the
    ///   connection ended before the event came.
    func suspendConnectionHookWait<Detail: Sendable>(
        unless eventCame: Bool,
        throwingIf connectionEnded: Bool,
        in store: @escaping TestHookWaiterStore<MCPServer, ConnectionHookWaitEnd, Detail>,
        detail: Detail
    ) async throws {
        guard !eventCame else { return }
        guard !connectionEnded else { throw ConnectionHookWaitError.connectionEnded }
        let end = await TestHookWait.suspend(
            on: self,
            in: store,
            detail: detail,
            cancelValue: ConnectionHookWaitEnd.cancelled,
            resolvedValue: { nil },
            didRecord: { resumeConnectionHookWaitRecordedWaiters() })
        try end.throwIfConnectionEnded()
    }

    /// Whether a wait of ``waitUntilTransportDropped()`` or of
    /// ``waitUntilToolListChangedGeneration(reaches:)`` is recorded.
    private var hasRecordedConnectionHookWait: Bool {
        !transportDropWaiters.isEmpty || !toolListChangedGenerationWaiters.isEmpty
    }

    /// Resumes each wait of ``waitUntilConnectionHookWaitIsRecorded()`` — the
    /// step of ``suspendConnectionHookWait(unless:throwingIf:in:detail:)``
    /// when it records its wait.
    private func resumeConnectionHookWaitRecordedWaiters() {
        connectionHookWaitRecordedWaiters.resumeAll(with: ())
    }

    /// Ends each wait of ``waitUntilTransportDropped()`` and of
    /// ``waitUntilToolListChangedGeneration(reaches:)`` with
    /// ``ConnectionHookWaitEnd/connectionEnded`` — the step of a
    /// `disconnect()`: no drop and no notification of that connection comes
    /// any more.
    func endConnectionHookWaits() {
        transportDropWaiters.resumeAll(with: .connectionEnded)
        endToolListChangedGenerationWaits()
    }
}
