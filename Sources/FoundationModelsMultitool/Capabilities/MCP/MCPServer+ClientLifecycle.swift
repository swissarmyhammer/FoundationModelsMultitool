// `MCPServer+ClientLifecycle` — the new `MCP.Client` of each connect attempt,
// the install of the client of the current attempt, the teardown of an old
// client, and the set of transports that did not close yet.
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
// **The transport close is the event that callers wait for.** Each transport
// that an attempt made goes into ``MCPServer/openTransports`` when the
// factory gave it. The `DropObservingTransport` around it reports the return
// of the `disconnect()` of the wrapped transport, and that report takes the
// transport out of the set. A stdio transport kills and reaps its subprocess
// in its own `disconnect()`. Thus:
//
// - A connect attempt that replaces the current client waits until the
//   transport of that client closed, and only then calls the factory. A new
//   stdio subprocess is spawned only after the old one is gone.
// - `disconnect()` returns only when each transport of an earlier generation
//   closed: the transport of the current client, and the transport of each
//   straggler. A straggler that ends its connect after the teardown started
//   closes its own transport, and the teardown waits for that close too.
//
// No clock decides these waits. A transport whose `disconnect()` never
// returns makes its waiter wait, and so does a straggler whose `connect()`
// never returns, when `disconnect()` waits for it.

import MCP

extension MCPServer {
    /// The client of one connect attempt, and the transport it connects over.
    struct AttemptClient {
        /// The new client of the attempt.
        let client: MCP.Client

        /// The transport the client connects over: the wrapper around the
        /// transport that the factory gave.
        let transport: DropObservingTransport

        /// The id of the transport in ``MCPServer/openTransports``.
        let transportID: Int
    }

    /// One transport of ``MCPServer/openTransports`` that did not close yet.
    struct OpenTransport {
        /// The ``MCPServer/connectGeneration`` of the attempt that made it.
        let generation: Int

        /// Each caller that waits for the close of the transport.
        var closeWaiters: [CheckedContinuation<Void, Never>] = []
    }

    // MARK: - The client of an attempt

    /// Makes the client of one connect attempt for `transport`, and adds
    /// `transport` to ``openTransports``.
    ///
    /// The client gets each handler before its connect — see
    /// `setupHandlers(on:)` in `MCPServer+Connection.swift`. When
    /// `generation` is already stale, no client is made: `transport` is
    /// released through its `DisposableTransport` conformance when it has
    /// one, and it is never connected.
    ///
    /// - Parameters:
    ///   - transport: The transport that the factory gave.
    ///   - generation: The ``connectGeneration`` of the attempt.
    /// - Returns: The client and its transport, or `nil` when `generation`
    ///   is stale.
    func makeAttemptClient(over transport: any Transport, generation: Int) async -> AttemptClient? {
        let transportID = addOpenTransport(generation: generation)
        guard isCurrentGeneration(generation, orDiscard: .mcpStaleTransportDiscarded) else {
            await (transport as? DisposableTransport)?.dispose()
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
        let client = Client(name: name, version: clientVersion, capabilities: Self.clientCapabilities)
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

    // MARK: - The open transports

    /// Adds a transport of the attempt of `generation` to ``openTransports``.
    ///
    /// - Parameter generation: The ``connectGeneration`` of the attempt.
    /// - Returns: The id of the transport.
    private func addOpenTransport(generation: Int) -> Int {
        let transportID = nextTransportID
        nextTransportID += 1
        openTransports[transportID] = OpenTransport(generation: generation)
        return transportID
    }

    /// Takes the transport of `transportID` out of ``openTransports``, and
    /// resumes each caller that waits for its close. A no-op when the
    /// transport closed before.
    ///
    /// - Parameter transportID: The id of the transport that closed.
    func closeOpenTransport(_ transportID: Int) {
        guard let closed = openTransports.removeValue(forKey: transportID) else { return }
        for waiter in closed.closeWaiters {
            waiter.resume()
        }
    }

    /// Waits until the transport of `transportID` closed. Returns at once
    /// when it closed before.
    ///
    /// - Parameter transportID: The id of the transport.
    func waitUntilTransportClosed(_ transportID: Int) async {
        guard openTransports[transportID] != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            openTransports[transportID]?.closeWaiters.append(continuation)
            let awaited = transportCloseAwaitedWaiters
            transportCloseAwaitedWaiters = []
            for waiter in awaited {
                waiter.resume()
            }
        }
    }

    /// Waits until no transport of a generation before `generation` stays in
    /// ``openTransports``. A transport that an attempt of such a generation
    /// adds during the wait is waited for too.
    ///
    /// - Parameter generation: The first generation whose transports this
    ///   wait leaves alone: the transports of a connect that started later.
    func waitUntilTransportsClosed(before generation: Int) async {
        while let open = openTransports.first(where: { $0.value.generation < generation }) {
            await waitUntilTransportClosed(open.key)
        }
    }

    /// Waits until a caller waits for the close of an open transport — the
    /// event a test waits on to know that `disconnect()` waits for a
    /// transport.
    ///
    /// Internal, for `@testable import`: no product code waits here.
    func waitUntilTransportCloseIsAwaited() async {
        guard !openTransports.values.contains(where: { !$0.closeWaiters.isEmpty }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            transportCloseAwaitedWaiters.append(continuation)
        }
    }
}
