// `CancellationNotices` — the tasks that carry a `notifications/cancelled` to
// the wire, held so a disconnect can wait for them.
//
// eventplan.md § "Background tools and the completion token": "MCP requests
// get the advisory cancel and post `.cancelled` before the transport closes."
// The cancellation of a calling `Task` reaches `MCPServer.call` in the
// `onCancel` handler of `withTaskCancellationHandler`, which is synchronous
// and runs on the thread that cancelled. The notice itself is `async` — it
// settles the call on the actor and then sends over the client — so the
// handler starts a task for it. Nothing awaited that task before this type:
// a `disconnect()` that ran first found the call already failed as lost, and
// the notice never reached the wire.
//
// This ledger holds each such task from its start to its end. `disconnect()`
// drains the ledger before it tears the client down, thus every notice a
// cancellation started is on the wire before the transport closes. A plain
// `final class` over a `Mutex`, and never an actor, because the handler that
// records into it cannot `await`.

import Synchronization

/// The tasks that carry a `notifications/cancelled` to the wire, from the
/// cancellation that started each one to the send that ends it.
final class CancellationNotices: Sendable {
    /// One task for each notice in flight, keyed by the order it started.
    private let inFlight = Mutex<[Int: Task<Void, Never>]>([:])

    /// The counter that gives each notice its key.
    private let keys = SequentialKeys()

    /// Creates an empty ledger.
    init() {}

    /// Starts a task that runs `notice`, and holds it until `notice` returns.
    ///
    /// Callable from a synchronous `onCancel` handler: the record is taken
    /// under the lock, and the task removes itself once `notice` returns.
    ///
    /// - Parameter notice: The work that carries the notice to the wire.
    func track(_ notice: @escaping @Sendable () async -> Void) {
        let key = keys.take()
        let task = Task {
            await notice()
            self.forget(key)
        }
        inFlight.withLock { $0[key] = task }
    }

    /// Waits until every notice that was in flight when this was called has
    /// reached the wire, or failed to.
    func drain() async {
        let pending = inFlight.withLock { Array($0.values) }
        for task in pending {
            await task.value
        }
    }

    /// Drops the record of the notice under `key` — it reached the wire, or
    /// it failed to.
    ///
    /// - Parameter key: The key of the notice.
    private func forget(_ key: Int) {
        inFlight.withLock { $0[key] = nil }
    }
}
