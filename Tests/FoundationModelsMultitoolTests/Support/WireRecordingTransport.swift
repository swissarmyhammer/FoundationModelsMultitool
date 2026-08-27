// `WireRecordingTransport` — a transport that records the order of what
// crosses it: each message the client sends, by its JSON-RPC method, and the
// disconnect that closes it.
//
// A test of the session-end sweep must prove an ORDER on the wire: the
// advisory `notifications/cancelled` goes out before the transport closes.
// `ScriptedServer.recordedNotifications` tells what the server received, and
// it says nothing about when the transport closed. This double stands on the
// client end of the same in-memory pair, so one ledger holds every send and
// the close, in the order the client made them. A test also appends a marker
// of its own, so an event of the run plane — the terminal of a swept run —
// stands in the same ledger beside the wire.

import Foundation
import Logging
import MCP

/// A `Transport` over a real, connectible transport, which records each send
/// by method and the disconnect in one ordered ledger.
actor WireRecordingTransport: WrappingTransport {
    /// One entry of the ledger.
    enum Entry: Equatable, Sendable {
        /// The client sent a message whose JSON-RPC method is `method`.
        case sent(method: String)

        /// The client disconnected the transport.
        case disconnected

        /// A test appended `label` — an event outside the wire, placed in
        /// the order it happened relative to the wire.
        case marker(String)
    }

    /// The key of a JSON-RPC message that names its method.
    private static let methodKey = "method"

    /// What ``Entry/sent(method:)`` carries for a message with no method —
    /// a response, which a client sends for a server-initiated request.
    private static let responseMethod = "(response)"

    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// Every entry, in the order it happened.
    private(set) var ledger: [Entry] = []

    /// The logger of this double — a no-op.
    nonisolated let logger = WireRecordingTransport.noOpLogger(
        label: "mcp.transport.wire-recording")

    /// Wraps `wrapped`, delegating every real operation to it.
    ///
    /// - Parameter wrapped: The transport to delegate to.
    init(wrapping wrapped: any Transport) {
        self.wrapped = wrapped
    }

    /// Delegates to the wrapped transport.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        try await connectWrapped()
    }

    /// Records the method of `data`, then delegates the send.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        ledger.append(.sent(method: Self.method(of: data)))
        try await wrapped.send(data)
    }

    /// Records the disconnect, then delegates it.
    func disconnect() async {
        ledger.append(.disconnected)
        await wrapped.disconnect()
    }

    /// Appends a marker of the test's own.
    ///
    /// - Parameter label: What the marker stands for.
    func mark(as label: String) {
        ledger.append(.marker(label))
    }

    /// Whether the ledger holds `entry`.
    ///
    /// - Parameter entry: The entry to look for.
    /// - Returns: `true` when the ledger holds it.
    func holds(_ entry: Entry) -> Bool {
        ledger.contains(entry)
    }

    /// The position of the first `entry` in the ledger.
    ///
    /// - Parameter entry: The entry to look for.
    /// - Returns: Its position, or `nil` when the ledger does not hold it.
    func position(of entry: Entry) -> Int? {
        ledger.firstIndex(of: entry)
    }

    /// The JSON-RPC method `data` names, or ``responseMethod``.
    ///
    /// - Parameter data: The raw bytes of one message.
    /// - Returns: The method.
    private static func method(of data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?[methodKey] as? String ?? responseMethod
    }
}
