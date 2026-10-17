// `CancellationHonoringTransport` — a transport whose send obeys the
// cancellation of the task that sends.
//
// The in-memory transport sends also from a cancelled task. A real transport
// does not always do that: `HTTPClientTransport` sends each message through
// `URLSession`, and `URLSession` stops the request when the task that sends is
// cancelled. This double gives that behavior to the in-memory pair: a send
// from a cancelled task throws `CancellationError`, and the message does not
// go to the far end. A test thus proves that a notice goes out from a task
// that is not cancelled.

import Foundation
import Logging
import MCP

/// A `Transport` over a real, connectible transport, whose send throws
/// `CancellationError` when the task that sends is cancelled.
actor CancellationHonoringTransport: WrappingTransport {
    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// The logger of this double — a no-op.
    nonisolated let logger = CancellationHonoringTransport.noOpLogger(
        label: "mcp.transport.cancellation-honoring")

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

    /// Throws when the task that sends is cancelled, else delegates the send.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: `CancellationError` when the task that sends is cancelled;
    ///   else what the `send(_:)` of the wrapped transport throws.
    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        try await wrapped.send(data)
    }
}
