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

    /// Blocks until ``release()`` is called, then delegates to the wrapped
    /// transport.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        connectWasCalled = true
        await gate.wait()
        try await connectWrapped()
    }

    /// Opens the gate: resumes a `connect()` already blocked on it, and lets
    /// every future `connect()` proceed at once.
    func release() async {
        await gate.release()
    }
}
