// `DropObservingTransport` — the transport `MCPServer` connects its client
// over: it delegates every operation to the transport the factory built, and
// it reports the end of the receive stream of that transport.
//
// **Why the server watches the transport itself.** swift-sdk 0.12.1's
// `MCP.Client` resumes a pending request in two places only: `disconnect()`
// and `cancelRequest(_:reason:)`. When the transport drops under the client,
// its message loop catches the error of the receive stream, logs it and
// stops, and every pending `tools/call` waits forever. Nothing on the client
// says the connection is gone. This wrapper is where the server learns it:
// the receive stream the client iterates is a mirror of the wrapped one, and
// the task that relays it reports the end of the wrapped stream — finished or
// thrown — to `MCPServer.handleTransportDrop(generation:)`, which fails every
// in-flight call as `.lost`.
//
// **A disconnect the client asked for is not a drop.** `MCP.Client.disconnect()`
// calls the `disconnect()` of this wrapper, and the wrapped stream ends as a
// result. That end is the host's own doing, and it is not reported.
//
// **`import Logging` names ONE type, and logs nothing.** The sdk's `Transport`
// protocol requires `var logger: Logging.Logger`, so this actor names the
// type to conform, as `StdioServerProcess.swift` does. It writes nothing
// through it.

import struct Foundation.Data
import Logging
import MCP

/// A `Transport` that delegates to the transport it wraps and reports the
/// end of that transport's receive stream — see the header of this file.
actor DropObservingTransport: Transport {
    /// The label of the no-op logger of this wrapper.
    private static let loggerLabel = "mcp.transport.drop-observing"

    /// The transport every operation delegates to.
    private let wrapped: any Transport

    /// What the relay task calls once the wrapped receive stream ended
    /// without a ``disconnect()`` of this wrapper — the drop report.
    private let onDrop: @Sendable () async -> Void

    /// The mirror of the wrapped receive stream, built by ``connect()``.
    ///
    /// `Transport.receive()` is not `async`, so this actor cannot fetch the
    /// stream of `wrapped` on demand; ``connect()`` fetches it and builds the
    /// mirror, and ``receive()`` returns the mirror.
    private var mirroredReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// Whether ``disconnect()`` ran on this wrapper — read by the relay task
    /// once the wrapped stream ended, to tell the host's disconnect from a
    /// drop.
    private var wasDisconnected = false

    /// The logger of this wrapper — a no-op. `Transport.logger` is a
    /// `nonisolated` requirement that cannot be read off the wrapped
    /// transport (an existential actor reference) without an actor hop.
    nonisolated let logger = Logging.Logger(
        label: DropObservingTransport.loggerLabel,
        factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// Wraps `wrapped`.
    ///
    /// - Parameters:
    ///   - wrapped: The transport to delegate to.
    ///   - onDrop: Called one time, after the receive stream of `wrapped`
    ///     ended without a ``disconnect()`` of this wrapper.
    init(wrapping wrapped: any Transport, onDrop: @escaping @Sendable () async -> Void) {
        self.wrapped = wrapped
        self.onDrop = onDrop
    }

    /// Delegates to the wrapped transport, then builds the mirror of its
    /// receive stream for ``receive()``.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        try await wrapped.connect()
        mirroredReceiveStream = mirror(await wrapped.receive())
    }

    /// Records the disconnect, so the end of the wrapped stream it causes
    /// is not reported as a drop, then delegates to the wrapped transport.
    func disconnect() async {
        wasDisconnected = true
        await wrapped.disconnect()
    }

    /// Delegates to the wrapped transport.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    /// The mirror of the wrapped receive stream, built by the most recent
    /// ``connect()`` — or a finished empty stream when no `connect()` ran.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let mirroredReceiveStream else {
            return AsyncThrowingStream { $0.finish() }
        }
        return mirroredReceiveStream
    }

    /// Builds the stream the client iterates: every element of `inner`, and
    /// the same end, relayed by one task that then reports a drop.
    ///
    /// - Parameter inner: The receive stream of the wrapped transport.
    /// - Returns: The mirror.
    private func mirror(
        _ inner: AsyncThrowingStream<Data, Swift.Error>
    ) -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    for try await data in inner {
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.reportDropUnlessDisconnected()
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    /// Calls ``onDrop`` unless ``disconnect()`` ran on this wrapper — the
    /// one place the end of the wrapped stream is classified.
    private func reportDropUnlessDisconnected() async {
        guard !wasDisconnected else { return }
        await onDrop()
    }
}
