// `DisposableSpyTransport` — a transport that records whether it was ever
// connected, and whether it was disposed instead.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/DisposableSpyTransport.swift`
// over `WrappingTransport`.

import struct Foundation.Data
import Logging
import MCP

@testable import FoundationModelsMultitool

/// A `Transport` that also conforms to `DisposableTransport`, recording
/// whether `connect()` was ever called and whether `dispose()` was ever called
/// — the oracle that proves a connect attempt of `MCPServer` disposes of, and
/// never connects, a factory-built transport it discards as stale.
///
/// Wraps a real, connectible transport, so a test of the NON-stale path (an
/// ordinary successful connect) still runs a real handshake through it — only
/// the two recorded flags tell "was this used" from "was this discarded".
actor DisposableSpyTransport: WrappingTransport, DisposableTransport {
    let wrapped: any Transport
    var wrappedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// Whether `connect()` was ever called on this instance — `true` only
    /// when `MCPServer` wired this transport into `MCP.Client.connect(transport:)`,
    /// which must never happen for an instance ``disposeWasCalled`` reports
    /// `true` for.
    private(set) var connectWasCalled = false

    /// Whether `dispose()` was ever called on this instance.
    private(set) var disposeWasCalled = false

    /// The logger of this double — a no-op.
    nonisolated let logger = DisposableSpyTransport.noOpLogger(
        label: "mcp.transport.disposable-spy")

    /// Wraps `wrapped`, delegating every real operation to it.
    ///
    /// - Parameter wrapped: The transport to delegate to.
    init(wrapping wrapped: any Transport) {
        self.wrapped = wrapped
    }

    /// Records the call, then delegates to the wrapped transport.
    ///
    /// - Throws: What the `connect()` of the wrapped transport throws.
    func connect() async throws {
        connectWasCalled = true
        try await connectWrapped()
    }

    /// Records the call — the `DisposableTransport` conformance of this
    /// double.
    func dispose() async {
        disposeWasCalled = true
    }
}
