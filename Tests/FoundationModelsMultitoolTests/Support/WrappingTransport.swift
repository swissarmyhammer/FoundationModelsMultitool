// `WrappingTransport` — the delegation every transport double of this target
// shares.
//
// The source of these doubles (`GatedConnectTransport`,
// `GatedDisconnectTransport` and `DisposableSpyTransport` of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/`) carried
// the same `send`, `disconnect` and `receive` delegation, and the same cached
// receive stream, three times. Here the delegation stands one time, in an
// `Actor`-constrained protocol extension, so each method runs on the isolation
// of the conforming double. A double overrides the one operation it scripts.
//
// **`import Logging` names ONE type, and logs nothing.** The sdk's `Transport`
// protocol requires `var logger: Logging.Logger`, so a double names the type
// to conform. This target declares no `swift-log` product; the transitive one
// the sdk brings satisfies the import — see `mcpPackage` in `Package.swift`.

import struct Foundation.Data
import Logging
import MCP

/// A transport double that wraps a real, connectible transport and delegates
/// every operation it does not script to it.
///
/// `Transport.receive()` is not `async`, so a wrapper cannot cross into the
/// wrapped actor inside `receive()`. ``connectWrapped()`` fetches and caches
/// the receive stream of the wrapped transport right after it delegates the
/// connect, which mirrors how every real caller sequences `connect()` before
/// `receive()`, and ``receive()`` returns the cached stream.
protocol WrappingTransport: Actor, Transport {
    /// The transport every unscripted operation delegates to.
    var wrapped: any Transport { get }

    /// The receive stream of ``wrapped``, cached by the most recent
    /// successful ``connectWrapped()``.
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>? { get set }
}

extension WrappingTransport {
    /// Delegates the connect to the wrapped transport and caches its receive
    /// stream for ``receive()``.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connectWrapped() async throws {
        try await wrapped.connect()
        wrappedReceiveStream = await wrapped.receive()
    }

    /// Delegates the disconnect to the wrapped transport.
    func disconnect() async {
        await wrapped.disconnect()
    }

    /// Delegates the send to the wrapped transport.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    /// Returns the receive stream of the wrapped transport, cached by the
    /// most recent successful ``connectWrapped()``.
    ///
    /// - Returns: The cached stream, or a finished empty stream when no
    ///   connect succeeded yet.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let wrappedReceiveStream else {
            return AsyncThrowingStream { $0.finish() }
        }
        return wrappedReceiveStream
    }

    /// A no-op logger for a double — `Transport.logger` is a `nonisolated`
    /// requirement that cannot be read off the wrapped transport (an
    /// existential actor reference) without an actor hop.
    ///
    /// - Parameter label: The label of the logger.
    /// - Returns: A logger that writes nothing.
    static func noOpLogger(label: String) -> Logger {
        Logger(label: label, factory: { _ in SwiftLogNoOpLogHandler() })
    }
}
