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
        let waiterID = nextTestHookWaiterID
        nextTestHookWaiterID += 1
        await TestHookWait.suspend(
            on: self,
            cancelValue: (),
            resolvedValue: { hasRecordedConnectionHookWait ? () : nil },
            record: { continuation in connectionHookWaitRecordedWaiters[waiterID] = continuation },
            end: { server, _ in server.connectionHookWaitRecordedWaiters.removeValue(forKey: waiterID)?.resume() })
    }

    /// Whether a wait of ``waitUntilTransportDropped()`` or of
    /// ``waitUntilToolListChangedGeneration(reaches:)`` is recorded.
    private var hasRecordedConnectionHookWait: Bool {
        !transportDropWaiters.isEmpty || !toolListChangedGenerationWaiters.isEmpty
    }

    /// Resumes each wait of ``waitUntilConnectionHookWaitIsRecorded()`` — the
    /// step each connection hook runs when it records its wait.
    func resumeConnectionHookWaitRecordedWaiters() {
        connectionHookWaitRecordedWaiters.resumeAll(returning: ())
    }

    /// Ends each wait of ``waitUntilTransportDropped()`` and of
    /// ``waitUntilToolListChangedGeneration(reaches:)`` with
    /// ``ConnectionHookWaitEnd/connectionEnded`` — the step of a
    /// `disconnect()`: no drop and no notification of that connection comes
    /// any more.
    func endConnectionHookWaits() {
        transportDropWaiters.resumeAll(returning: .connectionEnded)
        endToolListChangedGenerationWaits()
    }
}
