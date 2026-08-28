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
// **A drop ends the mirror with an error, and never without one.** The message
// loop of `MCP.Client` is `repeat { for try await data in await
// connection.receive() } while true`. It leaves that loop when its task is
// cancelled, or when the stream ends with a THROW, which its `catch` breaks on.
// A stream that ends with no error sends the loop straight back to `receive()`,
// which gives back that same ended stream, and the loop then spins hot on one
// cooperative-pool thread for the life of the process. Nothing cancels that
// task: `handleTransportDrop(generation:)` fails the calls in flight and leaves
// the client where it is. So every end this wrapper reports as a drop carries
// an error, and so does the stream of a wrapper that never connected.
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

    /// The error the mirror ends with when the wrapped receive stream ended
    /// under a connected client and threw nothing of its own, and the error the
    /// stream of a wrapper that never connected ends with.
    ///
    /// The end has to carry an error, or the message loop of `MCP.Client` spins
    /// — see the header of this file. `MCPError.connectionClosed` is what the
    /// sdk's own `InMemoryTransport` ends a peer's stream with on a
    /// disconnection, and `MCPServer` already reads it as the loss of a call.
    private static let dropError = MCPError.connectionClosed

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
    /// ``connect()`` — or a stream that ends with ``dropError`` when no
    /// `connect()` ran. That end carries an error for the reason the header of
    /// this file states.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let mirroredReceiveStream else {
            return AsyncThrowingStream { $0.finish(throwing: Self.dropError) }
        }
        return mirroredReceiveStream
    }

    /// Builds the stream the client iterates: every element of `inner`, and an
    /// end that ``end(_:after:)`` classifies.
    ///
    /// - Parameter inner: The receive stream of the wrapped transport.
    /// - Returns: The mirror.
    private func mirror(
        _ inner: AsyncThrowingStream<Data, Swift.Error>
    ) -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream { continuation in
            let relay = Task {
                var failure: (any Swift.Error)?
                do {
                    for try await data in inner {
                        continuation.yield(data)
                    }
                } catch {
                    failure = error
                }
                await self.end(continuation, after: failure)
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    /// Ends `continuation` and reports a drop — the one place the end of the
    /// wrapped stream is classified.
    ///
    /// A ``disconnect()`` of this wrapper caused this end, thus the end stands
    /// as the wrapped stream gave it and nothing is reported. Otherwise the end
    /// is a drop: it carries ``dropError`` when the wrapped stream threw
    /// nothing of its own, and ``onDrop`` is called.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of the mirror.
    ///   - failure: What the wrapped stream threw, or `nil` when it ended with
    ///     no error.
    private func end(
        _ continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation,
        after failure: (any Swift.Error)?
    ) async {
        guard !wasDisconnected else {
            continuation.finish(throwing: failure)
            return
        }
        continuation.finish(throwing: failure ?? Self.dropError)
        await onDrop()
    }
}
