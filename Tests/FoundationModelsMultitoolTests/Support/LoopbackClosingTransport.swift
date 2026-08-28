// `LoopbackClosingTransport` — a transport double that stops its
// `LoopbackHTTPServer` when it disconnects.
//
// `MCPTestSupport.clientTransport(serving:over:)` builds a fresh
// `LoopbackHTTPServer` for every `.http` connect. It hands back only the
// `HTTPClientTransport` over it. It does not hand back the loopback itself.
// The static registry of `LoopbackHTTPServer` is the only strong reference
// that keeps such a loopback alive. Nothing releases it, and its live SSE
// stream stays open, until something calls `stop()` on it. A suite that
// never calls `MCPServer.disconnect()` (or `Client.disconnect()`) leaves
// that stream open, and holds the one process-wide gate of
// `LoopbackHTTPServer`, for the rest of the test process. Every later `.http`
// connect of the process then parks on that gate for ever.
//
// This double ties the loopback's lifetime to the one disconnect every
// suite already owes its client at the end of a test. Wrapping the
// `HTTPClientTransport` in it means `disconnect()` closes the wrapped
// transport first, then stops the loopback. So the registry entry and the
// open stream both end when the test does.

import struct Foundation.Data
import Logging
import MCP
import MCPTestServer

/// Wraps an `HTTPClientTransport` and stops the ``LoopbackHTTPServer`` it
/// connects to when it disconnects.
actor LoopbackClosingTransport: WrappingTransport {
    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The loopback ``disconnect()`` stops, after the wrapped transport ends.
    private let loopback: LoopbackHTTPServer

    /// The logger of this double — a no-op.
    nonisolated let logger = LoopbackClosingTransport.noOpLogger(
        label: "mcp.transport.loopback-closing")

    /// Creates a wrapper that stops `loopback` on disconnect.
    ///
    /// - Parameters:
    ///   - wrapped: The `HTTPClientTransport` to delegate every operation to.
    ///   - loopback: The loopback `wrapped` connects to, to stop.
    init(wrapping wrapped: any Transport, stopping loopback: LoopbackHTTPServer) {
        self.wrapped = wrapped
        self.loopback = loopback
    }

    /// Delegates to the wrapped transport. The connect itself stops
    /// nothing.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        try await connectWrapped()
    }

    /// Delegates to the wrapped transport, then stops the loopback. This
    /// ends the live SSE stream this connect held open. It also ends the
    /// registry entry that would otherwise hold the loopback for the rest
    /// of the test process.
    func disconnect() async {
        await wrapped.disconnect()
        await loopback.stop()
    }
}
