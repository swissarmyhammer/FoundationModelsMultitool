// `HangingTransport` — a transport whose `connect()` never returns.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/HangingTransport.swift`.

import struct Foundation.Data
import Logging
import MCP

/// A `Transport` whose `connect()` never returns and never checks
/// `Task.isCancelled` — a wedged real-world transport (a stuck subprocess
/// spawn, a stalled handshake) that never observes cooperative cancellation,
/// so the per-attempt `BackoffPolicy.connectTimeout` of `MCPServer` is proven
/// to bound wall-clock time for real.
///
/// Deliberately not `Task.sleep(for:)`: that suspends through the
/// cancellation-aware timer of the runtime, so a race that cancels its losing
/// child would still return promptly against it, and mask the bug this double
/// exists to catch. A `withCheckedContinuation` that is never resumed, with no
/// cancellation handler, never returns once suspended, whatever cancellation
/// the calling task later receives.
///
/// - Important: Every test that uses this prints a `SWIFT TASK CONTINUATION
///   MISUSE` warning to stderr per hung attempt — expected, not a bug: the
///   runtime notices the never-resumed continuation being deallocated.
actor HangingTransport: Transport {
    /// The logger of this double — a no-op; it never connects.
    nonisolated let logger = Logger(
        label: "mcp.transport.hanging",
        factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// Never returns, and does not respond to cancellation.
    func connect() async throws {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Never resumed: this is the point.
        }
    }

    /// This double has nothing to disconnect.
    func disconnect() async {}

    /// Always throws: this double never reaches a connected state.
    ///
    /// - Parameter data: Ignored.
    /// - Throws: `MCPError.internalError`, always.
    func send(_ data: Data) async throws {
        throw MCPError.internalError("HangingTransport never connects")
    }

    /// Returns an empty receive stream; this double never produces data.
    ///
    /// - Returns: A stream that yields nothing.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream { _ in }
    }
}
