// `GatedDisconnectTransport` — a transport whose `disconnect()` waits for a
// gate.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/GatedDisconnectTransport.swift`
// over `WrappingTransport` and `ReleaseGate`.

import struct Foundation.Data
import Logging
import MCP

/// A `Transport` wrapper whose `disconnect()` blocks until ``release()`` is
/// called, then delegates to the wrapped transport — the disconnect-side
/// counterpart of ``GatedConnectTransport``.
///
/// `MCP.Client.disconnect()` takes its connection state first, and then
/// awaits the `disconnect()` of its transport before it returns — so this
/// gate holds a real `client.disconnect()` call open, and the transport open,
/// for as long as a test needs. That is what proves that a fresh connect of
/// `MCPServer` does not wait for a disconnect whose transport does not close,
/// and that the late close of an old transport never closes the current
/// connection.
actor GatedDisconnectTransport: WrappingTransport {
    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The gate `disconnect()` waits on.
    private let gate = ReleaseGate()

    /// The gate that `disconnect()` opens when it is called. A
    /// `client.disconnect()` calls it only after it took the state of the
    /// client, thus a test waits on it to know that the take occurred.
    let disconnectArrival = TestGate()

    /// The logger of this double — a no-op.
    nonisolated let logger = GatedDisconnectTransport.noOpLogger(
        label: "mcp.transport.gated-disconnect")

    /// Creates a gated wrapper around `wrapped`, with the gate closed.
    ///
    /// - Parameter wrapped: The transport to delegate to.
    init(wrapping wrapped: any Transport) {
        self.wrapped = wrapped
    }

    /// Delegates to the wrapped transport — the connect itself is never
    /// gated by this type.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        try await connectWrapped()
    }

    /// Opens ``disconnectArrival``, blocks until ``release()`` is called,
    /// then delegates to the wrapped transport.
    func disconnect() async {
        disconnectArrival.open()
        await gate.wait()
        await wrapped.disconnect()
    }

    /// Opens the gate: resumes a `disconnect()` already blocked on it, and
    /// lets every future `disconnect()` proceed at once.
    func release() async {
        await gate.release()
    }
}
