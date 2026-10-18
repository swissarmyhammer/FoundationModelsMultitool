import FoundationModelsExtras
import Synchronization

/// The inner `tools.*` calls of one `runCode` invocation that are in flight,
/// kept so the cancellation of the invocation reaches each one at once.
///
/// **The gap this closes.** The JS bridge runs each `tools.*` call in a
/// `Task` of its own, started from a JSC callback outside every task tree
/// (see `RunBinding`). Cancelling the `Task` that runs `MultiTool.call`
/// therefore reaches the snippet — the interpreter cancels the run — and
/// reaches no inner call directly: the run cancels the pending bridge tasks
/// in a cancel job on its own job queue, after the cancellation was
/// requested. eventplan.md § "Background tools and the completion token"
/// fixes an order at session end: "MCP requests get the advisory cancel and
/// post `.cancelled` before the transport closes." The sweep that cancels a
/// parked `runCode` run returns as soon as the cancellation is requested, and
/// the host closes the transports right after it. A cancel that reaches the
/// in-flight MCP call one job later can reach it after the transport closed.
///
/// So each inner call runs in a `Task` this record holds, and
/// `MultiTool.runCapturingOutcome(code:installing:installingAsync:using:cancelling:)`
/// cancels every one of them from its own cancellation handler —
/// synchronously, in the same `cancel()` that reached the invocation. The
/// cancellation then reaches `MCPServer.call` before the sweep returns.
///
/// A reference type guarded by a `Mutex`, rather than an `actor`, for
/// `LostRunRecord`'s reason: the recording side runs inside
/// `AsyncHostFunction` bodies the interpreter's promise pump starts on
/// whatever thread it likes, and ``cancelAll()`` runs inside a cancellation
/// handler, which cannot `await`.
///
/// **The lease of a call that outlives its snippet.** A call that is still in
/// flight when the code of its snippet ends is work that lives past that
/// code: the snippet did not await it (see ``SnippetEndMark``). From that
/// moment until the call ends, the call holds one
/// `FoundationModelsExtras/WorkKind/innerCall` lease in the work registry of
/// the session of the `runCode` call (see ``markSnippetEnded()``). A call
/// that the snippet awaited ends before the snippet code ends, thus it never
/// holds a lease: the `runCode` call itself, or the run-plane lease of its
/// background run, already holds the session. A call that a cancel ends
/// ends its lease when its task ends.
final class InFlightInnerCalls: Sendable {
    /// One inner call in flight.
    private struct Entry: Sendable {
        /// The task that runs the call.
        let task: Task<InterpreterValue, any Error>

        /// The name of the binding that was called.
        let name: InnerCallName

        /// The lease of the call, from the moment the snippet code ended, or
        /// `nil` while the snippet code runs and on a bare run.
        var lease: BackgroundWork?
    }

    /// One entry for each inner call in flight, keyed by the order it
    /// started.
    private let entries = Mutex<[Int: Entry]>([:])

    /// The counter that gives each call its key.
    private let keys = SequentialKeys()

    /// The context of the `runCode` call, whose work registry each lease goes
    /// into, or `nil` for a run with no session.
    private let context: ToolContext?

    /// The moment the code of the snippet of this run ended.
    private let snippetEnd: SnippetEndMark

    /// Creates an empty record.
    ///
    /// - Parameters:
    ///   - context: The context of the `runCode` call, or `nil` for a run
    ///     with no session. A call in a child session leases in the registry
    ///     of the child, because the context is the context of that session.
    ///   - snippetEnd: The mark of the end of the snippet code of this run.
    init(leasingIn context: ToolContext?, after snippetEnd: SnippetEndMark) {
        self.context = context
        self.snippetEnd = snippetEnd
    }

    /// Runs one `tools.*` call in a task this record holds while the call is
    /// in flight, and forwards the cancellation of the caller to that task.
    ///
    /// A call that starts after the snippet code ended holds its lease from
    /// its start. The lease ends when the task of the call ended.
    ///
    /// - Parameters:
    ///   - name: The name of the binding that is called.
    ///   - call: The `tools.*` binding to run.
    /// - Returns: What `call` returned, unchanged.
    /// - Throws: Whatever `call` throws, unchanged.
    func running(
        _ name: InnerCallName,
        _ call: @escaping @Sendable () async throws -> InterpreterValue
    ) async throws -> InterpreterValue {
        let key = keys.take()
        let task = Task { try await call() }
        entries.withLock { entries in
            // The flag is read under the lock, after the insert. Thus
            // ``markSnippetEnded()`` leases this entry, or this read sees
            // the end of the snippet code and leases it here.
            var entry = Entry(task: task, name: name)
            if snippetEnd.hasEnded {
                entry.lease = lease(for: name)
            }
            entries[key] = entry
        }
        defer {
            let ended = entries.withLock { $0.removeValue(forKey: key) }
            ended?.lease?.end()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Records that the code of the snippet ended, and begins the lease of
    /// each call that is still in flight — what the snippet end host
    /// function calls.
    ///
    /// The leases begin before this call returns: a lease is open before the
    /// snippet gives its result.
    func markSnippetEnded() {
        snippetEnd.markEnded()
        entries.withLock { entries in
            for (key, entry) in entries where entry.lease == nil {
                entries[key]?.lease = lease(for: entry.name)
            }
        }
    }

    /// Cancels every inner call in flight — what the cancellation of the
    /// invocation itself calls, from its own cancellation handler.
    func cancelAll() {
        let inFlight = entries.withLock { $0.values.map(\.task) }
        for task in inFlight {
            task.cancel()
        }
    }

    /// Begins the lease of the call of `name`, or gives `nil` on a run with
    /// no session.
    ///
    /// The id of the lease is the completion token of the `runCode` call,
    /// then `/tools.` and the path of the binding, for example
    /// `"01J…/tools.shell.execute"`.
    ///
    /// - Parameter name: The name of the binding.
    /// - Returns: The lease, or `nil`.
    private func lease(for name: InnerCallName) -> BackgroundWork? {
        guard let context else { return nil }
        return context.beginBackgroundWork(.innerCall, id: "\(context.completionToken)/tools.\(name.path)")
    }
}
