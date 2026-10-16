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
// **A disconnect the host asked for is not a drop.** `MCP.Client.disconnect()`
// and the teardown of `MCPServer` call the `disconnect()` of this wrapper, and
// the wrapped stream ends as a result. That end is the host's own doing, and
// it is not reported. It still ends the mirror with an error — see below.
//
// **The close is reported.** When the `disconnect()` of the wrapped transport
// returns, the transport is closed: a stdio transport killed and reaped its
// subprocess. This wrapper then reports the close to
// `MCPServer.closeOpenTransport(_:)`. A connect attempt and `disconnect()`
// of the server wait for that report, and never for the end of the
// `disconnect()` of the client, which can hang on a suspended server-to-client
// handler — see `MCPServer+ClientLifecycle.swift`.
//
// **Every end of the mirror throws.** The message loop of `MCP.Client` is
// `repeat { for try await data in await connection.receive() } while true`. It
// leaves that loop when its task is cancelled, or when the stream ends with a
// THROW, which its `catch` breaks on. A stream that ends with no error sends
// the loop straight back to `receive()`, and the loop then spins hot on one
// cooperative-pool thread until its task is cancelled. After a drop, nothing
// cancels that task: `handleTransportDrop(generation:)` fails the calls in
// flight and leaves the client where it is. After a disconnect of this
// wrapper, the loop can still run too: the teardown of `MCPServer` stops the
// loop of the client before it calls the `disconnect()` of this wrapper
// itself, but a client whose connect was still on its way can start its loop
// after that stop. So each end throws:
//
// - A drop ends the mirror with the error of the wrapped stream, or with
//   `MCPError.connectionClosed` when the wrapped stream threw nothing.
// - A disconnect of this wrapper ends the mirror with
//   `DropObservingTransport.Disconnected`.
// - Each `receive()` after the end gives a stream that throws the same error
//   at once. The stream of a wrapper that never connected throws too.
//
// **The relay reads one notification before the client.** The message loop of
// `MCP.Client` calls the handler of a server-to-client request inline. Under a
// bound `ToolContext`, the `elicitation/create` handler of a URL-mode question
// holds the loop until the flow completes, thus the loop cannot read the
// `notifications/elicitation/complete` that completes the flow. This wrapper
// reads each frame before it yields the frame to the client. For that
// notification, it awaits ``onElicitationComplete`` first, and it yields the
// frame after. Thus the frame order stays as the server sent it: a drop after
// the completion reaches the server only after the completion did.
//
// **`import Logging` names ONE type, and logs nothing.** The sdk's `Transport`
// protocol requires `var logger: Logging.Logger`, so this actor names the
// type to conform, as `StdioServerProcess.swift` does. It writes nothing
// through it.

import struct Foundation.Data
import class Foundation.JSONDecoder
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

    /// The error the mirror ends with after a ``disconnect()`` of this
    /// wrapper, and the error each later ``receive()`` stream ends with.
    ///
    /// The host asked for this end, thus it is not a drop, and nothing is
    /// reported. The end still has to carry an error, or the message loop of
    /// `MCP.Client` spins — see the header of this file. A type of its own
    /// keeps this end apart from ``dropError``.
    struct Disconnected: Error {}

    /// The transport every operation delegates to.
    private let wrapped: any Transport

    /// What the relay task calls once the wrapped receive stream ended
    /// without a ``disconnect()`` of this wrapper — the drop report.
    private let onDrop: @Sendable () async -> Void

    /// What ``disconnect()`` calls once the `disconnect()` of the wrapped
    /// transport returned — the report that the transport is closed.
    private let onClose: @Sendable () async -> Void

    /// What the relay task awaits for each
    /// `notifications/elicitation/complete` frame, with the wire
    /// `elicitationId` of the frame, before it yields that frame to the client.
    /// The relay yields no later frame until this call returns, thus the frame
    /// order stays as the server sent it.
    ///
    /// The swift-sdk client calls a request handler inline in its message
    /// loop, thus a held `elicitation/create` handler stops the loop, and the
    /// client cannot read this notification. This hook reads it before the
    /// loop. Elicitation-plan task 42 (the swift-sdk handles a
    /// server-to-client request off the receive loop) can make this hook
    /// unnecessary later: then a notification handler on the client can read
    /// the frame while the request handler waits.
    private let onElicitationComplete: @Sendable (String) async -> Void

    /// The mirror of the wrapped receive stream, built by ``connect()``.
    ///
    /// `Transport.receive()` is not `async`, so this actor cannot fetch the
    /// stream of `wrapped` on demand; ``connect()`` fetches it and builds the
    /// mirror, and ``receive()`` returns the mirror.
    private var mirroredReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The error the mirror ended with, or `nil` while the mirror did not
    /// end. Set by ``end(_:after:)`` before it ends the mirror, and cleared
    /// by ``connect()`` when it builds a new mirror.
    ///
    /// A stream that ended gives no error to a second reader, thus
    /// ``receive()`` gives a new stream that throws this error.
    private var endError: (any Swift.Error)?

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
    ///   - onClose: Called at the end of each ``disconnect()``, once the
    ///     `disconnect()` of the wrapped transport returned. Defaults to no
    ///     report.
    ///   - onElicitationComplete: Awaited with the wire `elicitationId` of
    ///     each `notifications/elicitation/complete` frame, before the relay
    ///     yields that frame. Defaults to no relay.
    init(
        wrapping wrapped: any Transport,
        onDrop: @escaping @Sendable () async -> Void,
        onClose: @escaping @Sendable () async -> Void = {},
        onElicitationComplete: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.wrapped = wrapped
        self.onDrop = onDrop
        self.onClose = onClose
        self.onElicitationComplete = onElicitationComplete
    }

    /// The one close of this wrapper: the `disconnect()` of the wrapped
    /// transport, then the report through ``onClose``. Made by the first
    /// ``disconnect()``; each later ``disconnect()`` waits for the same close.
    private var close: Task<Void, Never>?

    /// Delegates to the wrapped transport, then builds the mirror of its
    /// receive stream for ``receive()``.
    ///
    /// A wrapper that was closed never connects: the teardown of the server
    /// can close it before its client calls this method. When the close comes
    /// while the `connect()` of the wrapped transport runs, and that
    /// `connect()` then succeeds, this method closes the wrapped transport
    /// again and throws. Thus no transport stays open after its close.
    ///
    /// - Throws: `MCPError.connectionClosed` when this wrapper was closed;
    ///   otherwise what the `connect()` of the wrapped transport throws.
    func connect() async throws {
        guard !wasDisconnected else {
            throw Self.dropError
        }
        try await wrapped.connect()
        guard !wasDisconnected else {
            await wrapped.disconnect()
            throw Self.dropError
        }
        endError = nil
        mirroredReceiveStream = mirror(await wrapped.receive())
    }

    /// Records the disconnect, so the end of the wrapped stream it causes
    /// is not reported as a drop, delegates to the wrapped transport, and
    /// then reports the close through ``onClose``.
    ///
    /// The client of the attempt and the teardown of the server can both
    /// call this method. The wrapped transport closes one time, and each
    /// call returns once that close ended.
    func disconnect() async {
        wasDisconnected = true
        if close == nil {
            let wrapped = wrapped
            let onClose = onClose
            close = Task {
                await wrapped.disconnect()
                await onClose()
            }
        }
        await close?.value
    }

    /// Delegates to the wrapped transport.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    /// The mirror of the wrapped receive stream, built by the most recent
    /// ``connect()``, while that mirror did not end. Otherwise a stream that
    /// throws at once: the error the mirror ended with, or ``dropError`` when
    /// no `connect()` ran. Each end carries an error for the reason the header
    /// of this file states.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        if endError == nil, let mirroredReceiveStream {
            return mirroredReceiveStream
        }
        let failure = endError ?? Self.dropError
        return AsyncThrowingStream { $0.finish(throwing: failure) }
    }

    /// Builds the stream the client iterates: every element of `inner`, and an
    /// end that ``end(_:after:)`` classifies.
    ///
    /// For a `notifications/elicitation/complete` frame, the relay awaits
    /// ``onElicitationComplete`` before it yields the frame. The client has
    /// no handler for that notification, thus the yield does nothing more.
    ///
    /// - Parameter inner: The receive stream of the wrapped transport.
    /// - Returns: The mirror.
    private func mirror(
        _ inner: AsyncThrowingStream<Data, Swift.Error>
    ) -> AsyncThrowingStream<Data, Swift.Error> {
        let onElicitationComplete = onElicitationComplete
        return AsyncThrowingStream { continuation in
            let relay = Task {
                var failure: (any Swift.Error)?
                do {
                    for try await data in inner {
                        if let elicitationId = Self.completedElicitationId(in: data) {
                            await onElicitationComplete(elicitationId)
                        }
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

    /// The wire shape of a `notifications/elicitation/complete` frame: only
    /// the fields that the relay reads.
    private struct CompletionFrame: Decodable {
        /// The method of the frame.
        let method: String

        /// The params of the frame.
        let params: ElicitationCompleteNotification.Parameters
    }

    /// The UTF-8 bytes of the method name of the completion notification. A
    /// frame that does not hold them is not decoded.
    private static let completionMethodBytes = Data(ElicitationCompleteNotification.name.utf8)

    /// The wire `elicitationId` of `frame` when `frame` is one
    /// `notifications/elicitation/complete` notification.
    ///
    /// A frame that does not hold the method name is not decoded, thus the
    /// relay decodes no tool result.
    ///
    /// - Parameter frame: One frame of the wrapped receive stream.
    /// - Returns: The wire id, or `nil` for each other frame.
    static func completedElicitationId(in frame: Data) -> String? {
        guard frame.range(of: completionMethodBytes) != nil,
            let decoded = try? JSONDecoder().decode(CompletionFrame.self, from: frame),
            decoded.method == ElicitationCompleteNotification.name
        else {
            return nil
        }
        return decoded.params.elicitationId
    }

    /// Ends `continuation` and reports a drop — the one place the end of the
    /// wrapped stream is classified.
    ///
    /// When a ``disconnect()`` of this wrapper caused this end, the end
    /// carries ``Disconnected``, and nothing is reported. Otherwise the end is
    /// a drop: it carries what the wrapped stream threw, or ``dropError`` when
    /// the wrapped stream threw nothing, and ``onDrop`` is called. Each end
    /// throws, for the reason the header of this file states.
    ///
    /// The error goes into ``endError`` before the mirror ends. Thus a reader
    /// that saw the end and then calls ``receive()`` gets the same error.
    ///
    /// - Parameters:
    ///   - continuation: The continuation of the mirror.
    ///   - failure: What the wrapped stream threw, or `nil` when it ended with
    ///     no error.
    private func end(
        _ continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation,
        after failure: (any Swift.Error)?
    ) async {
        let isDrop = !wasDisconnected
        let endedWith: any Swift.Error = isDrop ? failure ?? Self.dropError : Disconnected()
        endError = endedWith
        continuation.finish(throwing: endedWith)
        guard isDrop else { return }
        await onDrop()
    }
}
