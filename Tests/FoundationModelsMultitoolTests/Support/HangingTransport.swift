// `HangingTransport` — a transport whose `connect()` never returns.
//
// A behavioral port of
// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/Support/HangingTransport.swift`.

import Logging
import MCP
import TestConcurrency

/// A `Transport` whose `connect()` never returns a result — a wedged
/// real-world transport (a stuck subprocess spawn, a stalled handshake), so
/// the per-attempt `BackoffPolicy.connectTimeout` of `MCPServer` is proven to
/// bound wall-clock time for real.
///
/// Deliberately not `Task.sleep(for:)`: that sleep ends when its time is
/// spent, and then the attempt would end without the timeout. The hang of
/// this double ends only when the task of the attempt is cancelled. The
/// connect attempt of `MCPServer` runs in a task that nothing cancels, thus
/// the attempt hangs until the timeout abandons it.
///
/// The hang keeps its continuation in a ``WaitList`` until a cancel ends it.
/// Thus the runtime never finds a released continuation that was not
/// resumed, and writes no `SWIFT TASK CONTINUATION MISUSE` line.
///
/// ``NeverConnectingTransport`` supplies the disconnect, send and receive
/// stubs.
actor HangingTransport: NeverConnectingTransport {
    /// The logger of this double — a no-op; it never connects.
    nonisolated let logger = Logger(
        label: "mcp.transport.hanging",
        factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// Never returns. It ends only with a `CancellationError`, when the task
    /// of the caller is cancelled.
    ///
    /// - Throws: `CancellationError` when the task of the caller is
    ///   cancelled.
    func connect() async throws {
        try await Self.hangUntilCancelled()
    }

    /// Suspends the calling task until the task is cancelled — the hang of
    /// this double, shared with a peer that must make no progress. A scripted
    /// tool whose handler calls this is a server that never answers the
    /// request.
    ///
    /// No event resumes the wait, thus only a cancel ends it. The wait list
    /// keeps the continuation, and its cancel handler resumes the
    /// continuation exactly one time (test rule T1).
    ///
    /// - Throws: `CancellationError` when the task of the caller is
    ///   cancelled, also before the call. It never returns.
    static func hangUntilCancelled() async throws -> Never {
        let noEvent = WaitList<Void>()
        await noEvent.wait(for: ())
        throw CancellationError()
    }
}
