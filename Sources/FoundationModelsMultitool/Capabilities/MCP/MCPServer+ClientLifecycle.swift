// `MCPServer+ClientLifecycle` — the new `MCP.Client` of each connect attempt,
// the install of the client of the current attempt, the teardown of an old
// client, and the set of attempts whose transport did not close yet.
//
// **Why a new client for each attempt.** `MCP.Client.connect(transport:)`
// changes the connection and the message-handling task of the client, and it
// gives no way to cancel it. A connect attempt can pass its `connectTimeout`
// and still run inside that call: a straggler. When one client is used for
// each attempt, the straggler and the retry change the same client, and two
// message loops read one receive stream. When each attempt makes its own
// client, the straggler changes only its own client. The server already
// dropped that client: the generation guard (`connectGeneration`,
// `isCurrentGeneration(_:orDiscard:error:)`) discards the late result, and
// the straggler tears its own client down. Nothing that a straggler does can
// touch the current connection, thus no attempt waits for another attempt.
//
// **Which client is current.** ``MCPServer/currentClient`` holds the client of
// the current connection. Only the attempt whose generation is still current
// sets it, and only after its `initialize` handshake succeeded. The install
// comes before the discovery of the tools, thus a `tools/list_changed` that
// arrives during the discovery re-lists over the new connection. If the
// generation becomes stale during the discovery, the attempt takes its client
// out again and tears it down. A new attempt and `disconnect()` take the
// current client out and tear it down.
//
// **A teardown that no caller waits for.** An old client is torn down with
// its own `disconnect()`, in a task that no caller waits on.
// `MCP.Client.disconnect()` closes its transport, and then waits for the end
// of its message-handling task. That wait does not end while a
// server-to-client request handler is suspended on that connection. Thus the
// call can hang, and it hangs alone.
//
// **The set of open attempts.** Each connect attempt goes into
// ``MCPServer/openTransports`` when it starts, before it calls the factory.
// When the factory gives a transport, the attempt adds the
// `DropObservingTransport` around it to its entry. The entry leaves the set
// when the transport closed — the wrapper reports the return of the
// `disconnect()` of the wrapped transport — or when the attempt ended with no
// transport to close: the factory threw, or the attempt was stale when the
// factory returned and released the transport at once. A stdio transport
// kills and reaps its subprocess in its own `disconnect()`. Thus:
//
// - A connect attempt that replaces the current client waits until the
//   transport of that client closed, and only then calls the factory. A new
//   stdio subprocess is spawned only after the old one is gone.
// - `disconnect()` ends each attempt of an earlier generation. It calls the
//   `disconnect()` of each transport in the set itself, also the transport of
//   a straggler whose `connect()` did not return, and waits for each close. It
//   waits for each attempt whose factory did not return yet: that attempt is
//   stale when its factory returns, and it releases the transport at once and
//   never connects it. Thus no transport and no stdio subprocess of an
//   earlier attempt can stay or appear after `disconnect()` returned.
//
// No clock decides these waits. A transport whose `disconnect()` never
// returns makes its waiter wait, and so does a factory that never returns,
// when `disconnect()` waits for it.

import MCP

extension MCPServer {
    /// The client of one connect attempt, and the transport it connects over.
    struct AttemptClient {
        /// The new client of the attempt.
        let client: MCP.Client

        /// The transport the client connects over: the wrapper around the
        /// transport that the factory gave.
        let transport: DropObservingTransport

        /// The id of the attempt in ``MCPServer/openTransports``.
        let transportID: Int
    }

    /// One attempt of ``MCPServer/openTransports`` whose transport did not
    /// close yet.
    struct OpenTransport {
        /// The ``MCPServer/connectGeneration`` of the attempt.
        let generation: Int

        /// The transport of the attempt, or `nil` while its factory did not
        /// return.
        var transport: DropObservingTransport?

        /// Each caller that waits for the close of the transport.
        var closeWaiters: [CheckedContinuation<Void, Never>] = []
    }

    // MARK: - The client of an attempt

    /// Adds a connect attempt of `generation` to ``openTransports`` — the
    /// first step of each attempt, before it calls the factory.
    ///
    /// - Parameter generation: The ``connectGeneration`` of the attempt.
    /// - Returns: The id of the attempt.
    func beginAttempt(generation: Int) -> Int {
        let transportID = nextTransportID
        nextTransportID += 1
        openTransports[transportID] = OpenTransport(generation: generation)
        return transportID
    }

    /// Makes the client of the attempt `transportID` for `transport`, the
    /// transport that its factory gave.
    ///
    /// The client gets each handler before its connect — see
    /// `setupHandlers(on:)` in `MCPServer+Connection.swift`. When
    /// `generation` is already stale, no client is made: `transport` is
    /// released at once — through its `DisposableTransport` conformance when
    /// it has one, else through its `disconnect()` — and it is never
    /// connected.
    ///
    /// - Parameters:
    ///   - transport: The transport that the factory gave.
    ///   - transportID: The id of the attempt in ``openTransports``.
    ///   - generation: The ``connectGeneration`` of the attempt.
    /// - Returns: The client and its transport, or `nil` when `generation`
    ///   is stale.
    func makeAttemptClient(
        over transport: any Transport, transportID: Int, generation: Int
    ) async -> AttemptClient? {
        guard isCurrentGeneration(generation, orDiscard: .mcpStaleTransportDiscarded) else {
            if let disposable = transport as? DisposableTransport {
                await disposable.dispose()
            } else {
                await transport.disconnect()
            }
            closeOpenTransport(transportID)
            return nil
        }
        // The wrapper outlives this call — the client holds it for the whole
        // connection — so its reports hold this actor weakly.
        let observed = DropObservingTransport(
            wrapping: transport,
            onDrop: { [weak self] in
                await self?.handleTransportDrop(generation: generation)
            },
            onClose: { [weak self] in
                await self?.closeOpenTransport(transportID)
            })
        openTransports[transportID]?.transport = observed
        let client = Client(
            name: name, version: clientVersion, capabilities: Self.clientCapabilities(for: userPresence))
        await setupHandlers(on: client)
        return AttemptClient(client: client, transport: observed, transportID: transportID)
    }

    /// Takes `attempt` out of ``currentClient`` when it is the current
    /// client, and tears its client down in a task that no caller waits on.
    ///
    /// A client that was torn down before is torn down again with no effect:
    /// its `disconnect()` then has no connection to close.
    ///
    /// - Parameter attempt: The client to drop.
    func dropAttemptClient(_ attempt: AttemptClient) {
        if currentClient?.client === attempt.client {
            currentClient = nil
        }
        let client = attempt.client
        Task { await client.disconnect() }
    }

    /// Takes the current client out, tears it down, and waits until its
    /// transport closed. Returns at once when there is no current client.
    func retireCurrentClient() async {
        guard let retired = currentClient else { return }
        dropAttemptClient(retired)
        await waitUntilTransportClosed(retired.transportID)
    }

    // MARK: - The open attempts

    /// Takes the attempt of `transportID` out of ``openTransports``, and
    /// resumes each caller that waits for its close. A no-op when the
    /// attempt left the set before.
    ///
    /// - Parameter transportID: The id of the attempt whose transport closed,
    ///   or that ended with no transport to close.
    func closeOpenTransport(_ transportID: Int) {
        guard let closed = openTransports.removeValue(forKey: transportID) else { return }
        for waiter in closed.closeWaiters {
            waiter.resume()
        }
    }

    /// Waits until the attempt of `transportID` left ``openTransports``.
    /// Returns at once when it left before.
    ///
    /// - Parameter transportID: The id of the attempt.
    func waitUntilTransportClosed(_ transportID: Int) async {
        guard openTransports[transportID] != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            openTransports[transportID]?.closeWaiters.append(continuation)
            let awaited = transportCloseAwaitedWaiters
            transportCloseAwaitedWaiters = [:]
            for waiter in awaited.values {
                waiter.resume()
            }
        }
    }

    /// Ends each attempt of a generation before `generation`, and returns
    /// when none stays in ``openTransports``.
    ///
    /// For an attempt with a transport, this calls the `disconnect()` of
    /// that transport itself — also when its `connect()` did not return — and
    /// that call returns once the transport closed. For an attempt whose
    /// factory did not return, this waits: that attempt is stale, and it
    /// releases its transport at once when the factory returns. An attempt
    /// of such a generation that starts during the wait is ended too.
    ///
    /// - Parameter generation: The first generation whose attempts this
    ///   call leaves alone: the attempts of a connect that started later.
    func endAttempts(before generation: Int) async {
        while let (transportID, open) = openTransports.first(where: { $0.value.generation < generation }) {
            if let transport = open.transport {
                await transport.disconnect()
                closeOpenTransport(transportID)
            } else {
                await waitUntilTransportClosed(transportID)
            }
        }
    }

    /// Waits until a caller waits for the close of an open attempt — the
    /// event a test waits on to know that a teardown waits for an attempt.
    /// A cancel of the calling task ends the wait.
    ///
    /// Internal, for `@testable import`: no product code waits here.
    func waitUntilTransportCloseIsAwaited() async {
        guard !openTransports.values.contains(where: { !$0.closeWaiters.isEmpty }) else { return }
        let waiterID = nextTransportCloseAwaitedWaiterID
        nextTransportCloseAwaitedWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                transportCloseAwaitedWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task { await self.endTransportCloseAwaitedWait(waiterID) }
        }
    }

    /// Ends the wait `waiterID` of ``waitUntilTransportCloseIsAwaited()`` —
    /// the cancel of that wait. A no-op when the wait ended before.
    ///
    /// - Parameter waiterID: The id of the wait.
    private func endTransportCloseAwaitedWait(_ waiterID: Int) {
        transportCloseAwaitedWaiters.removeValue(forKey: waiterID)?.resume()
    }
}
