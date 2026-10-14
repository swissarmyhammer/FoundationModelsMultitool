// `MCPServer+ClientQueue` — the FIFO queue that serializes every
// `client.connect(transport:)` and `client.disconnect()` call of one
// `MCPServer`.
//
// A behavioral port of `enqueueClientOperation(kind:_:)`,
// `awaitWithBoundedWait(_:timeout:on:)`, `connectClientExclusively(transport:generation:)`
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
// **When a disconnect ends its turn.** `MCP.Client.disconnect()` first reads
// its logger with an `await` (`await connection?.logger`). Only after that
// `await` does it take its connection, its message-handling task and its
// pending requests, and set each one to empty. A connect that runs before
// that point gives the client its new connection, and the late disconnect
// then takes and closes that new connection. Thus no operation can pass a
// disconnect before the disconnect took the state. After that point the
// disconnect closes the connection it took, and then waits for the end of the
// message-handling task it took. That wait does not end while a
// server-to-client request handler is suspended on that connection, thus the
// call may never return. But nothing it does after the take changes the
// client again, so a later operation is safe once the take occurred.
//
// Thus a disconnect ends its turn at the first of two events, and no clock
// decides it:
//
// - The client calls `disconnect()` on the connection it took. Each
//   connection is a `DropObservingTransport`, and it reports that call to
//   `endClientDisconnectTurn()`. Before that call the sdk only resumes the
//   pending requests and cancels the task, and neither can hang.
// - `client.disconnect()` returns. This is the event when the client had no
//   connection to take. Then it also has no message-handling task to wait
//   for, and it returns at once.
//
// The 500 ms bound that stood here before protected the queue against the
// `client.disconnect()` call that does not return. The first event above
// protects against that case too, and it does not let an operation pass a
// disconnect that has not taken the state yet.
//
// **When the caller of a disconnect continues.** The caller of
// `disconnectClientWithoutHanging()` waits longer than the queue: until the
// transport that the client took closed, or until `client.disconnect()`
// returned. A stdio transport kills and reaps its subprocess in its
// `disconnect()`, thus `MCPServer.disconnect()` returns with that subprocess
// gone, and a connect attempt spawns its new subprocess only after that. The
// suspended server-to-client handler does not stop this wait, because the
// client waits for its message-handling task only after the transport
// closed.
//
// **Why the wait behind a connect is bounded.** `MCP.Client.connect(transport:)`
// spawns its receive-loop task only AFTER `transport.connect()` returns, and
// that task re-reads the connection when it runs. So an operation that waits
// behind an unresolved connect waits under ``clientConnectStragglerGracePeriod``.
// The bound cannot be infinite: a straggler that never finishes
// `transport.connect()` can never reach the dangerous step, and no reader can
// tell "wedged for good" from "slow so far" in advance, so a fresh attempt
// must be able to make progress past one.

import MCP

extension MCPServer {
    /// Which operation ``enqueueClientOperation(kind:_:)`` enqueues — the
    /// two are not interchangeable, because the event that lets the next
    /// operation start differs: a connect has a bound, and a disconnect ends
    /// its turn when it took the state of the client — see the header of
    /// this file.
    enum ClientOperationKind {
        /// A `client.connect(transport:)` call.
        case connect

        /// A `client.disconnect()` call.
        case disconnect
    }

    /// The two events of the running `client.disconnect()` call that a
    /// waiter waits for — see the header of this file.
    struct ClientDisconnectEvents {
        /// Finished when the call took the state of the client, or returned:
        /// the end of the queue turn of the disconnect operation.
        let stateTaken: AsyncStream<Void>.Continuation

        /// Finished when the transport that the call took closed, or when
        /// the call returned: the event the caller of
        /// `disconnectClientWithoutHanging()` waits for.
        let transportClosed: AsyncStream<Void>.Continuation
    }

    /// How many seconds ``clientConnectStragglerGracePeriod`` lasts.
    private static let clientConnectStragglerGraceSeconds = 5

    /// How long a queued operation waits for its predecessor when that
    /// predecessor is a `client.connect(transport:)` operation that is not
    /// resolved — see the header of this file for why this is finite.
    static let clientConnectStragglerGracePeriod = Duration.seconds(
        clientConnectStragglerGraceSeconds)

    /// Waits for `task` to finish, but no longer than `timeout` as `clock`
    /// measures it — when `task` has not finished by then, this returns
    /// anyway and leaves `task` running, never cancelled, in the background.
    ///
    /// Two independent, un-joined tasks resume one ``SingleResume``: the
    /// first to finish answers, and the other is discarded.
    ///
    /// - Parameters:
    ///   - task: The task to wait for.
    ///   - timeout: The maximum time to wait.
    ///   - clock: The clock the wait sleeps on — ``clientQueueClock``, the
    ///     real clock for a host.
    static func awaitWithBoundedWait(
        _ task: Task<Void, Never>, timeout: Duration, on clock: any Clock<Duration>
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = SingleResume<Void, Never>(continuation)
            Task {
                _ = await task.value
                resume.resume(with: .success(()))
            }
            Task {
                try? await clock.sleep(for: timeout)
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
    /// `operation` runs once the operation enqueued just before it finished.
    /// When that predecessor is a connect operation and
    /// ``pendingConnectStragglers`` is greater than zero at the moment this
    /// operation is enqueued, `operation` also runs once
    /// ``clientConnectStragglerGracePeriod`` elapsed. Behind a disconnect
    /// operation there is no bound: such an operation finishes once it took
    /// the state of the client — see `disconnectClientWithoutHanging()`. The
    /// chaining is synchronous — no `await` stands between the read of the
    /// tail and its replacement — so two calls are always ordered exactly as
    /// they were made on this actor.
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
        // is ALREADY enqueued decides whether this wait has a bound.
        let waitsUnderConnectBound = clientQueueTailKind == .connect && pendingConnectStragglers > 0
        if kind == .connect {
            pendingConnectStragglers += 1
        }
        let clock = clientQueueClock
        let task = Task<T, any Error> {
            if waitsUnderConnectBound {
                await Self.awaitWithBoundedWait(
                    previous, timeout: Self.clientConnectStragglerGracePeriod, on: clock)
            } else {
                await previous.value
            }
            defer {
                if kind == .connect { self.decrementPendingConnectStragglers() }
            }
            return try await operation()
        }
        clientQueueTail = Task<Void, Never> { _ = try? await task.value }
        clientQueueTailKind = kind
        let tailWaiters = clientQueueTailWaiters
        clientQueueTailWaiters = []
        for waiter in tailWaiters {
            waiter.resume()
        }
        return task
    }

    /// Waits until an operation entered the client queue after `tail` was
    /// its tail — the event a test of the queue waits on in place of a poll
    /// of ``clientQueueTail``. Returns at once when the tail is no longer
    /// `tail`.
    ///
    /// Internal, for `@testable import`: no product code waits here. Each
    /// call of `enqueueClientOperation(kind:_:)` sets a new tail, thus each
    /// call ends every wait.
    ///
    /// - Parameter tail: The tail the caller read before it started the
    ///   operation it waits for.
    func waitUntilClientQueueTailChanges(from tail: Task<Void, Never>) async {
        guard clientQueueTail == tail else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            clientQueueTailWaiters.append(continuation)
        }
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
    /// The client connects over a `DropObservingTransport` around
    /// `transport`, which reports the end of the receive stream of
    /// `transport` to `handleTransportDrop(generation:)`, and the
    /// `disconnect()` call of the client to `endClientDisconnectTurn()` — see
    /// `DropObservingTransport.swift`. The wrap comes after the
    /// `DisposableTransport` check above, which reads the conformance of the
    /// factory-built instance itself.
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
        // Built here, and not inside the queued operation: the wrapper
        // outlives this call — the client holds it for the whole connection —
        // so its reports hold this actor weakly, and no cycle stands.
        let observed = DropObservingTransport(
            wrapping: transport,
            onDrop: { [weak self] in
                await self?.handleTransportDrop(generation: generation)
            },
            onDisconnect: { [weak self] in
                await self?.endClientDisconnectTurn() ?? {}
            })
        let task = enqueueClientOperation(kind: .connect) { () async throws -> Initialize.Result? in
            guard
                await self.isCurrentGeneration(
                    generation,
                    orDiscard: .mcpStaleTransportDiscarded
                )
            else {
                await (transport as? DisposableTransport)?.dispose()
                return nil
            }
            return try await self.client.connect(transport: observed)
        }
        return try await task.value
    }

    /// Enqueues `client.disconnect()`, and returns once the transport that
    /// the call took closed, or once the call returned.
    ///
    /// The enqueue is synchronous, as the first thing this method does, so a
    /// connect enqueued right after it is chained to run strictly after this
    /// disconnect took the state. This method does not wait for the end of
    /// `client.disconnect()`, which may never come — see the header of this
    /// file. Every internal caller that needs the connection torn down
    /// routes through here, and never calls `client.disconnect()` directly.
    func disconnectClientWithoutHanging() async {
        let (transportClosed, transportClosedContinuation) = AsyncStream<Void>.makeStream()
        let task = enqueueClientOperation(kind: .disconnect) {
            await self.disconnectClientUntilItTookTheState(
                transportClosed: transportClosedContinuation)
        }
        _ = try? await task.value
        for await _ in transportClosed {}
    }

    /// Starts `client.disconnect()` in a task of its own, never cancelled,
    /// and returns at the first of two events: the call took the connection
    /// of the client (``endClientDisconnectTurn()``), or the call returned.
    ///
    /// The queued disconnect operation of `disconnectClientWithoutHanging()`
    /// runs this, thus the queue gives the next operation its turn at that
    /// event — see the header of this file.
    ///
    /// - Parameter transportClosed: Finished when the transport that the
    ///   call took closed, or when the call returned.
    private func disconnectClientUntilItTookTheState(
        transportClosed: AsyncStream<Void>.Continuation
    ) async {
        let (stateTaken, stateTakenContinuation) = AsyncStream<Void>.makeStream()
        runningClientDisconnect = ClientDisconnectEvents(
            stateTaken: stateTakenContinuation, transportClosed: transportClosed)
        let client = client
        Task {
            await client.disconnect()
            stateTakenContinuation.finish()
            transportClosed.finish()
        }
        for await _ in stateTaken {}
    }

    /// Ends the queue turn of the running `client.disconnect()` call — the
    /// report of a `DropObservingTransport` whose `disconnect()` the client
    /// called. The client calls it on the connection it took, thus the
    /// state of the client is already empty.
    ///
    /// A no-op when no disconnect operation is running.
    ///
    /// - Returns: The closure that the `DropObservingTransport` calls once
    ///   its wrapped transport closed. It ends the wait of the caller of
    ///   `disconnectClientWithoutHanging()`. The closure holds the events of
    ///   this one call, thus a later disconnect cannot get its report.
    func endClientDisconnectTurn() -> @Sendable () -> Void {
        guard let events = runningClientDisconnect else { return {} }
        runningClientDisconnect = nil
        events.stateTaken.finish()
        let transportClosed = events.transportClosed
        return { transportClosed.finish() }
    }
}
