// `HeldConnectTransport` — a transport whose `connect()` ends only when the
// test releases it, and which records a cancel of that connect.
//
// `HangingTransport` and `GatedConnectTransport` end their connect on a
// cancel. Thus a change that cancels a losing connect attempt and then waits
// for it does not hang with them, and their tests do not show that change.
// This double does not end on a cancel. It only records the cancel, thus a
// test can wait for the cancel as an event and fail at once.

import Logging
import MCP

/// A `Transport` whose `connect()` holds until the test calls
/// ``release()``, and then throws. A cancel of the task of the connect does
/// not end the hold: it only opens ``connectCancel``.
///
/// A test holds a losing connect attempt with this double, and reads three
/// events: the connect started (``connectArrival``), the task of the connect
/// was cancelled (``connectCancel``), and the connect ended
/// (``connectEnd``).
///
/// ``NeverConnectingTransport`` supplies the disconnect, send and receive
/// stubs.
actor HeldConnectTransport: NeverConnectingTransport {
    /// The logger of this double — a no-op; it never connects.
    nonisolated let logger = Logger(
        label: "mcp.transport.held-connect",
        factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// The gate that ``connect()`` opens when it is called, before it holds.
    nonisolated let connectArrival = TestGate()

    /// The gate that a cancel of the task of ``connect()`` opens. The hold
    /// does not end on the cancel.
    nonisolated let connectCancel = TestGate()

    /// The gate that ``connect()`` opens when it ended, by any path.
    nonisolated let connectEnd = TestGate()

    /// The gate that ``release()`` opens. It ends the hold of ``connect()``.
    private nonisolated let releaseGate = TestGate()

    /// Holds until ``release()`` is called, and then throws: this double
    /// never reaches a connected state.
    ///
    /// The hold waits in a task of its own, which no cancel reaches. Thus a
    /// cancel of the caller opens ``connectCancel`` and the hold continues.
    ///
    /// - Throws: `MCPError.connectionClosed`, always, after the release.
    func connect() async throws {
        connectArrival.open()
        defer { connectEnd.open() }
        let releaseGate = releaseGate
        let hold = Task { try? await releaseGate.wait() }
        await withTaskCancellationHandler {
            await hold.value
        } onCancel: {
            connectCancel.open()
        }
        throw MCPError.connectionClosed
    }

    /// Ends the hold of ``connect()``: a connect that holds now ends, and a
    /// later connect ends at once.
    nonisolated func release() {
        releaseGate.open()
    }

    /// Releases the hold, and waits until the connect that started ended.
    /// Returns at once when no connect started.
    ///
    /// A connect that started after the release ends at once, thus this
    /// call always returns.
    func releaseAndWaitForEnd() async {
        release()
        guard connectArrival.isOpen else { return }
        try? await connectEnd.wait()
    }
}
