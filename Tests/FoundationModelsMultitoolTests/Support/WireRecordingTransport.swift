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
//
// The double also records the `_meta` of each request that has one. A test of
// the trace propagation reads the `traceparent` that went out on the wire in
// the `_meta` of a `tools/call`.

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

    /// The `_meta` of one request that the client sent.
    struct SentMeta: Sendable {
        /// The JSON-RPC method of the request.
        let method: String

        /// Each field of the `_meta` of the request that has a string value,
        /// under its key.
        let fields: [String: String]
    }

    /// The key of a JSON-RPC message that names its method.
    private static let methodKey = "method"

    /// The key of a JSON-RPC message that holds its parameters.
    private static let paramsKey = "params"

    /// The key of the parameters that holds the `_meta` of a request.
    private static let metaKey = "_meta"

    /// What ``Entry/sent(method:)`` carries for a message with no method —
    /// a response, which a client sends for a server-initiated request.
    private static let responseMethod = "(response)"

    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// Every entry, in the order it happened.
    private(set) var ledger: [Entry] = []

    /// The `_meta` of each sent message that has one, in the order of the
    /// sends.
    private(set) var sentMetas: [SentMeta] = []

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

    /// Records the method of `data`, and its `_meta` when it has one, then
    /// delegates the send.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: What the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        let object = Self.jsonObject(of: data)
        let method = object?[Self.methodKey] as? String ?? Self.responseMethod
        ledger.append(.sent(method: method))
        if let meta = (object?[Self.paramsKey] as? [String: Any])?[Self.metaKey] as? [String: Any] {
            sentMetas.append(SentMeta(method: method, fields: meta.compactMapValues { $0 as? String }))
        }
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

    /// The JSON object of one message.
    ///
    /// - Parameter data: The raw bytes of one message.
    /// - Returns: The object, or `nil` when the bytes are not a JSON object.
    private static func jsonObject(of data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
