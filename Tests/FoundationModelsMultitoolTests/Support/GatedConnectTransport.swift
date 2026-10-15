// `GatedConnectTransport` — a transport whose `connect()` waits for a gate.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/GatedConnectTransport.swift`
// over `WrappingTransport` and `ReleaseGate`.

import struct Foundation.Data
import Logging
import MCP

/// A `Transport` wrapper whose `connect()` blocks until ``release()`` is
/// called, then delegates to the wrapped transport — a test controls exactly
/// when an in-flight connect attempt resolves, independent of how long a race
/// against `BackoffPolicy.connectTimeout` has already taken.
///
/// This is what proves the exhaustion path of
/// `MCPServer.connect(via:backoffPolicy:)` safe against a LATE-resolving (not
/// only a permanently hung, like ``HangingTransport``) abandoned attempt: hold
/// the gate closed past `connectTimeout` so the retry loop gives up, then
/// release it and confirm the now-late result of the orphaned attempt is
/// discarded.
actor GatedConnectTransport: WrappingTransport {
    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The gate `connect()` waits on.
    private let gate = ReleaseGate()

    /// The logger of this double — a no-op.
    nonisolated let logger = GatedConnectTransport.noOpLogger(label: "mcp.transport.gated-connect")

    /// Creates a gated wrapper around `wrapped`, with the gate closed.
    ///
    /// - Parameter wrapped: The transport to delegate to once released.
    init(wrapping wrapped: any Transport) {
        self.wrapped = wrapped
    }

    /// Whether ``connect()`` was called. It becomes true before the call
    /// waits on the gate, thus a test can wait for this event to know that
    /// the connect is in flight (card `^kdtrmhv`).
    private(set) var connectWasCalled = false

    /// The gate that ``connect()`` opens when it is called, before it waits
    /// on the release gate. A test waits on it to know that the connect is
    /// in flight, and does not poll ``connectWasCalled``.
    let connectArrival = TestGate()

    /// Whether the wrapped transport is open: `true` after a ``connect()``
    /// that succeeded, and `false` again after a ``disconnect()``. A test
    /// reads it to know that no open transport stays after a teardown.
    private(set) var isOpen = false

    /// The gate that ``disconnect()`` opens after the wrapped transport
    /// closed. A test waits on it to know that the transport closed, and
    /// does not poll ``isOpen``.
    let closeArrival = TestGate()

    /// Whether ``disconnect()`` was called. A ``connect()`` that waits on the
    /// gate then ends with an error, and never delegates.
    private(set) var isClosed = false

    /// Whether a ``connect()`` ended because ``disconnect()`` closed this
    /// transport while that connect waited on the gate.
    private(set) var connectEndedByClose = false

    /// The gate that ``connect()`` opens when it ended, by any path. A test
    /// waits on it to know that the connect ended, and then reads
    /// ``connectEndedByClose``.
    let connectEnd = TestGate()

    /// Blocks until ``release()`` is called, then delegates to the wrapped
    /// transport — or, when ``disconnect()`` closed this transport during the
    /// wait, ends with `MCPError.connectionClosed` and never delegates.
    ///
    /// - Throws: `MCPError.connectionClosed` when this transport was closed
    ///   during the wait; otherwise what the `connect()` of the wrapped
    ///   transport throws.
    func connect() async throws {
        connectWasCalled = true
        connectArrival.open()
        await gate.wait()
        defer { connectEnd.open() }
        guard !isClosed else {
            connectEndedByClose = true
            throw MCPError.connectionClosed
        }
        try await connectWrapped()
        isOpen = true
    }

    /// Records the close, ends a ``connect()`` that waits on the gate,
    /// delegates to the wrapped transport, then records the close and opens
    /// ``closeArrival``.
    func disconnect() async {
        isClosed = true
        await gate.release()
        await wrapped.disconnect()
        isOpen = false
        closeArrival.open()
    }

    /// Opens the gate: resumes a `connect()` already blocked on it, and lets
    /// every future `connect()` proceed at once.
    func release() async {
        await gate.release()
    }
}
