// `MCPServer+ClientQueue` — the FIFO queue that serializes every
// `client.connect(transport:)` and `client.disconnect()` call of one
// `MCPServer`.
//
// A behavioral port of `enqueueClientOperation(kind:_:)`,
// `awaitWithBoundedWait(_:timeout:)`, `connectClientExclusively(transport:generation:)`
// and `disconnectClientWithoutHanging()` of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`.
//
// **Why a queue.** `MCP.Client.connect(transport:)` mutates the connection and
// the message-handling task of the client as an unguarded side effect, and it
// gives no cooperative cancellation hook. A connect attempt that was current
// when it started that call can still be inside it when its own
// `connectTimeout` elapses, and the abandoned attempt keeps running for real.
// Without this queue, a fresh retry could call `client.connect(transport:)`
// again while that straggler is still inside its own call — two invocations
// on one `MCP.Client`, "two tasks racing to consume the same transport
// receive stream", which crashes.
//
// **Why a FIFO queue, and not a mutex.** A mutex gives no ordering between two
// callers that both wait on the same holder — including one fresh attempt's
// own disconnect (torn down first) and its own later connect, which must run
// in that order.
//
// **Why the wait is bounded, and why two bounds.** `MCP.Client.disconnect()`
// mutates its shared state synchronously, at the start, before anything that
// can hang; by the time it runs past a short grace period, there is nothing
// left for a later operation to race. `MCP.Client.connect(transport:)` is the
// opposite: it spawns its receive-loop task only AFTER `transport.connect()`
// returns, and that task re-reads the connection when it runs. So while any
// connect anywhere in the chain is unresolved, every enqueued operation waits
// under the far more generous connect bound. The bound cannot be infinite: a
// straggler that never finishes `transport.connect()` can never reach the
// dangerous step, and no reader can tell "wedged for good" from "slow so far"
// in advance, so a fresh attempt must be able to make progress past one.

import MCP

extension MCPServer {
    /// Which operation ``enqueueClientOperation(kind:_:)`` enqueues — the
    /// two are not interchangeable, because WHERE each one mutates the state
    /// of the client relative to its own potential hang point differs, and
    /// that difference is what makes a short bound safe for one and not the
    /// other — see the header of this file.
    enum ClientOperationKind {
        /// A `client.connect(transport:)` call.
        case connect

        /// A `client.disconnect()` call.
        case disconnect
    }

    /// How many milliseconds ``clientDisconnectGracePeriod`` lasts.
    private static let clientDisconnectGraceMilliseconds = 500

    /// How many seconds ``clientConnectStragglerGracePeriod`` lasts.
    private static let clientConnectStragglerGraceSeconds = 5

    /// How long a queued operation waits for its predecessor while no connect
    /// is unresolved anywhere in the queue, and how long `disconnect()` waits
    /// for `client.disconnect()` to return before it proceeds anyway.
    ///
    /// Generous against a healthy `disconnect()` (single-digit milliseconds),
    /// and still well under a user-visible delay for the pathological case
    /// this bounds: `MCP.Client.disconnect()` does not reliably return while a
    /// registered server-to-client request handler is suspended on the same
    /// connection, even though its effects take place at once.
    static let clientDisconnectGracePeriod = Duration.milliseconds(
        clientDisconnectGraceMilliseconds)

    /// How long a queued operation waits for its predecessor while some
    /// `client.connect(transport:)` operation is unresolved anywhere in the
    /// queue — see the header of this file for why this is finite, and why it
    /// is far more generous than ``clientDisconnectGracePeriod``.
    static let clientConnectStragglerGracePeriod = Duration.seconds(
        clientConnectStragglerGraceSeconds)

    /// Waits for `task` to finish, but no longer than `timeout` — when `task`
    /// has not finished by then, this returns anyway and leaves `task`
    /// running, never cancelled, in the background.
    ///
    /// Two independent, un-joined tasks resume one ``SingleResume``: the
    /// first to finish answers, and the other is discarded.
    ///
    /// - Parameters:
    ///   - task: The task to wait for.
    ///   - timeout: The maximum real wall-clock time to wait.
    static func awaitWithBoundedWait(_ task: Task<Void, Never>, timeout: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = SingleResume<Void, Never>(continuation)
            Task {
                _ = await task.value
                resume.resume(with: .success(()))
            }
            Task {
                try? await Task.sleep(for: timeout)
                resume.resume(with: .success(()))
            }
        }
    }

    /// Decrements ``pendingConnectStragglers`` once the real
    /// `client.connect(transport:)` call of an enqueued connect operation
    /// finished — the counterpart to the increment at enqueue time.
    private func decrementPendingConnectStragglers() {
        pendingConnectStragglers -= 1
    }

    /// Enqueues `operation` onto ``clientQueueTail`` and returns a task the
    /// caller awaits for the result of `operation`.
    ///
    /// `operation` runs once every operation enqueued before it finished —
    /// or once the bound elapsed: ``clientConnectStragglerGracePeriod`` when
    /// ``pendingConnectStragglers`` was greater than zero at the moment this
    /// operation was enqueued, and ``clientDisconnectGracePeriod`` otherwise.
    /// The chaining is synchronous — no `await` stands between the read of
    /// the tail and its replacement — so two calls are always ordered exactly
    /// as they were made on this actor.
    ///
    /// - Parameters:
    ///   - kind: Which operation `operation` performs. A `.connect` operation
    ///     increments ``pendingConnectStragglers`` here and decrements it
    ///     once `operation` finished.
    ///   - operation: The work to perform once its turn arrives. Never
    ///     cancelled by this method.
    /// - Returns: A task the caller awaits for the result of `operation`.
    func enqueueClientOperation<T: Sendable>(
        kind: ClientOperationKind, _ operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, any Error> {
        let previous = clientQueueTail
        // Read before the kind of this operation can affect the count: what
        // is ALREADY enqueued decides the bound of this wait.
        let timeout =
            pendingConnectStragglers > 0
            ? Self.clientConnectStragglerGracePeriod : Self.clientDisconnectGracePeriod
        if kind == .connect {
            pendingConnectStragglers += 1
        }
        let task = Task<T, any Error> {
            await Self.awaitWithBoundedWait(previous, timeout: timeout)
            defer {
                if kind == .connect { self.decrementPendingConnectStragglers() }
            }
            return try await operation()
        }
        clientQueueTail = Task<Void, Never> { _ = try? await task.value }
        return task
    }

    /// Waits its turn in the queue, then — when `generation` is still
    /// current once that turn arrives — calls `client.connect(transport:)` on
    /// `transport` and returns its result.
    ///
    /// The generation is re-checked here, inside the queued operation, and
    /// not before enqueuing: an attempt can go stale while it waits behind an
    /// earlier straggler. On the stale path `transport` is released through
    /// its `DisposableTransport` conformance when it has one, and never
    /// connected.
    ///
    /// - Parameters:
    ///   - transport: The transport to connect over.
    ///   - generation: The ``connectGeneration`` this attempt was launched
    ///     under.
    /// - Returns: The result of `client.connect(transport:)`, or `nil` when
    ///   `generation` had gone stale by the time the turn of this attempt
    ///   arrived.
    /// - Throws: What `client.connect(transport:)` throws.
    func connectClientExclusively(
        transport: any Transport, generation: Int
    ) async throws -> Initialize.Result? {
        let task = enqueueClientOperation(kind: .connect) { () async throws -> Initialize.Result? in
            guard
                await self.isCurrentGeneration(
                    generation,
                    orDiscard: "discarding a stale factory-built transport; a newer attempt started"
                )
            else {
                await (transport as? DisposableTransport)?.dispose()
                return nil
            }
            return try await self.client.connect(transport: transport)
        }
        return try await task.value
    }

    /// Enqueues `client.disconnect()` and waits for it no longer than
    /// ``clientDisconnectGracePeriod``.
    ///
    /// The enqueue is synchronous, as the first thing this method does, so a
    /// connect enqueued right after it is chained to run strictly after this
    /// disconnect — even when this method itself gave up waiting. Every
    /// internal caller that needs the connection torn down routes through
    /// here, and never calls `client.disconnect()` directly.
    func disconnectClientWithoutHanging() async {
        let task = enqueueClientOperation(kind: .disconnect) { await self.client.disconnect() }
        await Self.awaitWithBoundedWait(
            Task<Void, Never> { _ = try? await task.value },
            timeout: Self.clientDisconnectGracePeriod)
    }
}
