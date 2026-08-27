import Synchronization

/// The inner `tools.*` calls of one `runCode` invocation that are in flight,
/// kept so the cancellation of the invocation reaches each one at once.
///
/// **The gap this closes.** The JS bridge runs each `tools.*` call in a
/// `Task` of its own, started from a JSC callback outside every task tree
/// (see `RunBinding`). Cancelling the `Task` that runs `MultiTool.call`
/// therefore reaches the snippet — the interpreter's watchdog polls the
/// cancellation flag and terminates the run — and reaches no inner call
/// directly: the promise pump cancels the pending bridge tasks only on its
/// next poll, after the cancellation was requested. eventplan.md § "Background
/// tools and the completion token" fixes an order at session end: "MCP
/// requests get the advisory cancel and post `.cancelled` before the
/// transport closes." The sweep that cancels a parked `runCode` run returns
/// as soon as the cancellation is requested, and the host closes the
/// transports right after it. A cancel that reaches the in-flight MCP call one
/// poll later reaches it after the transport closed.
///
/// So each inner call runs in a `Task` this record holds, and
/// `MultiTool.run(code:installing:installingAsync:using:cancelling:)` cancels
/// every one of them from its own cancellation handler — synchronously, in the
/// same `cancel()` that reached the invocation. The cancellation then reaches
/// `MCPServer.call` before the sweep returns.
///
/// A reference type guarded by a `Mutex`, rather than an `actor`, for
/// `LostRunRecord`'s reason: the recording side runs inside
/// `AsyncHostFunction` bodies the interpreter's promise pump starts on
/// whatever thread it likes, and ``cancelAll()`` runs inside a cancellation
/// handler, which cannot `await`.
final class InFlightInnerCalls: Sendable {
    /// One task for each inner call in flight, keyed by the order it
    /// started.
    private let tasks = Mutex<[Int: Task<InterpreterValue, any Error>]>([:])

    /// The counter that gives each call its key.
    private let keys = SequentialKeys()

    /// Creates an empty record.
    init() {}

    /// Runs one `tools.*` call in a task this record holds while the call is
    /// in flight, and forwards the cancellation of the caller to that task.
    ///
    /// - Parameter call: The `tools.*` binding to run.
    /// - Returns: What `call` returned, unchanged.
    /// - Throws: Whatever `call` throws, unchanged.
    func running(
        _ call: @escaping @Sendable () async throws -> InterpreterValue
    ) async throws -> InterpreterValue {
        let key = keys.take()
        let task = Task { try await call() }
        tasks.withLock { $0[key] = task }
        defer { tasks.withLock { $0[key] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Cancels every inner call in flight — what the cancellation of the
    /// invocation itself calls, from its own cancellation handler.
    func cancelAll() {
        let inFlight = tasks.withLock { Array($0.values) }
        for task in inFlight {
            task.cancel()
        }
    }
}
