// `NeverConnectingTransport` — the stubs that each transport double shares
// when it never reaches a connected state.
//
// `HangingTransport` and `HeldConnectTransport` had the same `disconnect`,
// `send` and `receive` stubs. Here the stubs stand one time, in an
// `Actor`-constrained protocol extension, so each stub runs on the isolation
// of the conforming double. Each double keeps its own `connect()`, because
// the connect behavior of each double is different.

import struct Foundation.Data
import MCP

/// A transport double that never reaches a connected state. Its `connect()`
/// never succeeds, thus it has nothing to disconnect, it cannot send, and it
/// receives nothing.
///
/// A conforming double writes only its `connect()` and its `logger`. This
/// extension supplies `disconnect()`, `send(_:)` and `receive()`.
protocol NeverConnectingTransport: Actor, Transport {}

extension NeverConnectingTransport {
    /// This double has nothing to disconnect.
    func disconnect() async {}

    /// Always throws: this double never reaches a connected state.
    ///
    /// The message names the conforming double, for example
    /// "HangingTransport never connects".
    ///
    /// - Parameter data: Ignored.
    /// - Throws: `MCPError.internalError`, always.
    func send(_ data: Data) async throws {
        throw MCPError.internalError("\(Self.self) never connects")
    }

    /// Returns an empty receive stream; this double never produces data.
    ///
    /// - Returns: A stream that yields nothing.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream { _ in }
    }
}
