// `FlakyConnectTransport` — a transport whose first N connects fail.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/FlakyConnectTransport.swift`.
// Test support — see the header of `ScriptedServer.swift`.
//
// **`import Logging` names ONE type, and logs nothing.** The sdk's
// `Transport` protocol requires `var logger: Logging.Logger`, so this actor
// names the type to conform. This target declares no `swift-log` product;
// the transitive one the sdk brings satisfies the import, as it does for
// `StdioServerProcess.swift` — see `mcpPackage` in `Package.swift`.

import struct Foundation.Data
import Logging
import MCP

/// A `Transport` wrapper that fails the first `failingConnectAttempts` calls
/// to `connect()` with a scripted error, then delegates to the wrapped
/// transport on every attempt after — "fail-N-times-then-succeed connects".
///
/// Neither `Client.connect(transport:)` nor `Server.start(transport:)` has a
/// notion of a retried handshake; each calls `transport.connect()` one time.
/// To script a flaky handshake is to intercept that one call, which is what
/// this wrapper does; every other `Transport` requirement goes to the wrapped
/// transport.
///
/// `Transport.receive()` is not `async`, so a wrapper actor cannot cross into
/// a different actor (the wrapped transport) to fetch its stream inside
/// `receive()`. ``connect()`` fetches and caches the receive stream of the
/// wrapped transport right after it delegates, which mirrors how every real
/// caller sequences `connect()` before `receive()`, and ``receive()`` returns
/// the cached stream.
public actor FlakyConnectTransport: Transport {
    /// The transport every call delegates to once the scripted failures are
    /// spent.
    private let wrapped: any Transport

    /// How many leading `connect()` calls are still to fail.
    private var remainingFailures: Int

    /// The error each failing attempt throws.
    private let failureError: any Swift.Error

    /// The receive stream of `wrapped`, cached by the most recent successful
    /// ``connect()``.
    private var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The logger of this transport — `nonisolated`, as the `Transport`
    /// protocol requires. See the `logger` parameter of
    /// ``init(wrapping:failingConnectAttempts:error:logger:)`` for why it is
    /// not read off the wrapped transport.
    public nonisolated let logger: Logger

    /// How many `connect()` calls were made so far, successful or not.
    public private(set) var connectAttempts = 0

    /// Creates a flaky wrapper around `wrapped`.
    ///
    /// - Parameters:
    ///   - wrapped: The transport to delegate to once the scripted failures
    ///     are spent.
    ///   - failingConnectAttempts: How many leading `connect()` calls fail.
    ///     `0` means every call delegates at once.
    ///   - error: The error each failing attempt throws. Defaults to
    ///     `MCPError.connectionClosed`.
    ///   - logger: The logger for transport events. Defaults to a no-op
    ///     logger: `Transport.logger` is a `nonisolated` requirement that
    ///     cannot be read off `wrapped` (an existential actor reference)
    ///     without an actor hop, and a fresh no-op logger matches the default
    ///     of `InMemoryTransport`.
    public init(
        wrapping wrapped: any Transport,
        failingConnectAttempts: Int,
        error: any Swift.Error = MCPError.connectionClosed,
        logger: Logger? = nil
    ) {
        self.wrapped = wrapped
        self.remainingFailures = failingConnectAttempts
        self.failureError = error
        self.logger =
            logger
            ?? Logger(
                label: "mcp.transport.flaky-connect",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
    }

    /// Fails with the scripted error while failures remain, otherwise
    /// delegates to the `connect()` of the wrapped transport and caches its
    /// receive stream for ``receive()``.
    ///
    /// - Throws: The scripted `error` while failures remain; otherwise what
    ///   the `connect()` of the wrapped transport throws.
    public func connect() async throws {
        connectAttempts += 1
        guard remainingFailures <= 0 else {
            remainingFailures -= 1
            throw failureError
        }
        try await wrapped.connect()
        wrappedReceiveStream = await wrapped.receive()
    }

    /// Delegates the disconnect to the wrapped transport.
    public func disconnect() async {
        await wrapped.disconnect()
    }

    /// Delegates the send to the wrapped transport.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    public func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    /// Returns the receive stream of the wrapped transport, cached by the
    /// most recent successful ``connect()``.
    ///
    /// - Returns: The cached stream, or a finished empty stream when no
    ///   ``connect()`` succeeded yet.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let wrappedReceiveStream else {
            return AsyncThrowingStream { $0.finish() }
        }
        return wrappedReceiveStream
    }
}
