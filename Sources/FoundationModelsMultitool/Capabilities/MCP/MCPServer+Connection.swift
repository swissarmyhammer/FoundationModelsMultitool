// `MCPServer+Connection` — connect, disconnect, reconnect, and the backoff
// retry loop of one `MCPServer`.
//
// A behavioral port of `connect(via:)` in its four forms, `disconnect()`,
// `reconnectAfterFault()`, `performConnectAttempt(factory:timeout:)`,
// `applyConnect(via:generation:)`, `setupHandlers()` and the helpers of each
// of them, of `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`.
//
// **What `reconnect()` is.** The source reconnected from inside the call path,
// when a mid-call transport fault was noticed. The call path of this package
// never reconnects: a transport drop under an in-flight call fails that call
// as `MCPServerError.lost` (see `MCPServer+Call.swift`), and the reconnect
// itself — call the retained factory again, under the retained policy — is a
// host operation here, `reconnect()`.
//
// **What `setupHandlers(on:)` registers.** Two notification handlers and one
// request handler, on each new client before its connect — each attempt has
// its own client, see `MCPServer+ClientLifecycle.swift`. The
// `tools/list_changed` handler routes to the coalesced re-list of
// `MCPServer+LiveCatalog.swift`; the `progress` handler routes to the
// in-flight call of `MCPServer+Call.swift` whose token the notification
// names; the `elicitation/create` request handler routes to
// `MCPServer+Elicitation.swift`. The `DropObservingTransport` of the attempt,
// not the client, relays `notifications/elicitation/complete` to
// `MCPServer+Elicitation.swift`.
//
// **A connect discovers before it is ready.** `applyConnect(via:generation:)`
// runs the paginated `tools/list` of `MCPServer+Discovery.swift` right after
// the `initialize` handshake, and only then moves to `.ready` and emits the
// first `catalogUpdates` snapshot — a discovery failure faults the connect the
// same as a handshake failure does.
//
// **The per-attempt timeout races, and never joins.** A `withThrowingTaskGroup`
// implicitly awaits every child before it returns, and `MCP.Client.connect(transport:)`
// never checks `Task.isCancelled`, so a `Transport.connect()` that never
// returns would make a group-based race block as long as an un-raced call. The
// attempt runs as an independent, un-joined `Task`, and the connect returns as
// soon as the attempt or the timeout resumes the shared `SingleResume` first;
// the loser keeps running on its own client, and the generation guard
// discards its late result.

import Logging
import MCP

extension MCPServer {
    /// The base of the exponential backoff of `backoffDelay(afterAttempt:policy:)`
    /// — each failed attempt doubles the prior delay.
    private static let exponentialBackoffMultiplier = 2.0

    /// What one attempt inside the retry loop of
    /// ``connect(via:backoffPolicy:)-(TransportFactory,_)`` learned, for that
    /// loop to act on with one flat `switch`.
    private enum ConnectAttemptOutcome {
        /// The attempt succeeded; the loop returns.
        case connected

        /// The attempt failed and attempts remain; the loop sleeps this long
        /// before it tries again.
        case retryAfter(Duration)

        /// The attempt failed and no attempts remain; carries the failure the
        /// loop reports once every attempt is spent.
        case exhausted(any Error)

        /// The attempt failed with a `NonRetryableConnectError`; the loop
        /// gives up at once — no further attempt, no backoff sleep.
        case permanentFailure(any Error)
    }

    // MARK: - The public connect surface

    /// Connects the client to `transport`.
    ///
    /// A convenience over the factory-taking ``connect(via:)-(TransportFactory)``
    /// for a transport the host already constructed: `{ transport }` — a
    /// factory that always returns this same instance — is what is stored for
    /// a later ``reconnect()``.
    ///
    /// - Important: This overload does not support a stdio reconnect. A later
    ///   ``reconnect()`` retries `transport` itself, never a fresh one — safe
    ///   for a transport that re-establishes itself when reused, and useless
    ///   for a `StdioTransport` over a dead subprocess. Use the factory-taking
    ///   overload for a transport that must be freshly constructed.
    ///
    /// - Parameter transport: The transport to connect over, constructed and
    ///   owned by the host.
    /// - Throws: What `MCP.Client.connect(transport:)` throws.
    public func connect(via transport: any Transport) async throws {
        try await connect(via: { transport })
    }

    /// Connects the client to a transport built by `factory`.
    ///
    /// Calls `factory` one time here, and retains it so that a later
    /// ``reconnect()`` calls it again for a FRESH transport. Resets ``state``
    /// to `.connecting` at the start, advances it to `.ready` once the
    /// `initialize` handshake succeeds, and establishes ``identity`` on the
    /// first such success. On failure ``state`` becomes `.faulted`,
    /// ``identity`` stays as it was, and the error is rethrown.
    ///
    /// - Parameter factory: Builds (and, for a subprocess-backed transport,
    ///   spawns) a fresh `Transport` on demand.
    /// - Throws: What `factory` throws, or what `MCP.Client.connect(transport:)`
    ///   throws.
    public func connect(via factory: @escaping TransportFactory) async throws {
        transportFactory = factory
        recordConnectStart()
        // The generation moves first, thus an attempt still in flight is
        // stale before the current client is torn down. The factory runs
        // only after the transport of the current client closed.
        connectGeneration += 1
        let generation = connectGeneration
        await retireCurrentClient()
        try await applyConnect(via: factory, generation: generation)
    }

    /// Connects to `transport` with automatic retry under `backoffPolicy`.
    ///
    /// A convenience over the factory-taking
    /// ``connect(via:backoffPolicy:)-(TransportFactory,_)`` for a transport
    /// the host already constructed: `{ transport }` is what is retried on
    /// every attempt, and stored for a later ``reconnect()`` — with the stdio
    /// limitation ``connect(via:)-(any Transport)`` states.
    ///
    /// - Parameters:
    ///   - transport: The transport to connect over, retried on every attempt.
    ///   - backoffPolicy: The per-attempt timeout, the delay schedule, and the
    ///     maximum number of attempts.
    /// - Throws: ``MCPServerError/backoffExhausted(serverName:attempts:lastError:)``
    ///   once every attempt failed — never the raw error of the last attempt.
    public func connect(via transport: any Transport, backoffPolicy: BackoffPolicy) async throws {
        try await connect(via: { transport }, backoffPolicy: backoffPolicy)
    }

    /// Connects through `factory` with automatic retry under `backoffPolicy`,
    /// calling `factory` for a fresh transport on the first attempt and on
    /// every retry alike.
    ///
    /// Attempts up to `backoffPolicy.maxAttempts` times, each bounded by
    /// `backoffPolicy.connectTimeout`, and sleeps on the injected clock for an
    /// exponentially growing delay between failed attempts. A `factory` that
    /// throws fails that attempt like a transport whose own `connect()`
    /// throws — unless the error conforms to `NonRetryableConnectError`, in
    /// which case this fails at once after that one attempt, with no backoff
    /// delay, and throws
    /// ``MCPServerError/connectConfigurationFailed(serverName:underlying:)``.
    ///
    /// Records `factory` and `backoffPolicy` up front, so a later
    /// ``reconnect()`` calls `factory` again under this same policy.
    ///
    /// - Parameters:
    ///   - factory: Builds a fresh `Transport` on demand — one call per
    ///     attempt.
    ///   - backoffPolicy: The per-attempt timeout, the delay schedule, and the
    ///     maximum number of attempts.
    /// - Throws: ``MCPServerError/backoffExhausted(serverName:attempts:lastError:)``
    ///   once every attempt failed, or
    ///   ``MCPServerError/connectConfigurationFailed(serverName:underlying:)``
    ///   after one non-retryable failure — never the raw error of an attempt.
    public func connect(
        via factory: @escaping TransportFactory, backoffPolicy: BackoffPolicy
    ) async throws {
        activeBackoffPolicy = backoffPolicy
        transportFactory = factory
        var lastError: any Error = MCPServerError.notReady(.connecting)

        for attempt in 1...backoffPolicy.maxAttempts {
            let outcome = await attemptConnectionWithLogging(
                factory: factory, attempt: attempt, policy: backoffPolicy)
            switch outcome {
            case .connected:
                return
            case .retryAfter(let delay):
                try await clock.sleep(for: delay)
            case .exhausted(let error):
                lastError = error
            case .permanentFailure(let error):
                // No generation bump here, unlike the exhausted path below:
                // the factory of THIS attempt already ran to completion, and
                // `performConnectAttempt` bumped the generation at its start.
                throw MCPServerError.connectConfigurationFailed(
                    serverName: identityNameForDiagnostics, underlying: String(describing: error))
            }
        }

        // The final attempt may still be running in the background (it lost
        // the race against its own `connectTimeout`) — bump the generation
        // here too, so its late resolution is discarded instead of mutating
        // the state after the caller was told the connect failed.
        connectGeneration += 1
        record(
            .mcpConnectBackoffExhausted, level: .error,
            metadata: Self.attemptLimitMetadata(backoffPolicy)
                .merging(MultitoolTelemetry.errorMetadata(of: lastError)) { limit, _ in limit })
        throw MCPServerError.backoffExhausted(
            serverName: identityNameForDiagnostics,
            attempts: backoffPolicy.maxAttempts,
            lastError: String(describing: lastError))
    }

    /// Reconnects through the factory and under the policy of the most recent
    /// connect — for a host that noticed the connection is gone.
    ///
    /// Calls the retained ``transportFactory`` again for a fresh transport,
    /// which is what heals a dead stdio subprocess for real, and retries it
    /// under ``activeBackoffPolicy``. A server that only ever called the
    /// single-attempt `connect(via:)` reconnects under
    /// ``BackoffPolicy/default``.
    ///
    /// - Throws: ``MCPServerError/neverConnected`` when no `connect(via:)`
    ///   call ever ran, otherwise what
    ///   ``connect(via:backoffPolicy:)-(TransportFactory,_)`` throws.
    public func reconnect() async throws {
        guard let transportFactory else {
            throw MCPServerError.neverConnected
        }
        try await connect(via: transportFactory, backoffPolicy: activeBackoffPolicy)
        record(.mcpReconnected, level: .info)
    }

    /// Disconnects the client and moves ``state`` to `.disconnected`, without
    /// altering ``identity``.
    ///
    /// Waits first for every `notifications/cancelled` a cancelled calling
    /// `Task` started, so the advisory cancel is on the wire before the
    /// transport closes — eventplan.md § "Background tools and the completion
    /// token". Then bumps the generation, so a connect attempt still in
    /// flight when this runs is discarded instead of moving the state back to
    /// `.ready`, and cancels a `tools/list_changed` watcher still waiting out
    /// its coalesce window, so it re-lists nothing against the disconnected
    /// client. Every call still in flight ends as `MCPServerError.lost`: the
    /// answer it waited for can no longer arrive. A later `connect(via:)` is
    /// what drives the next transition.
    ///
    /// This method returns when the transport that the client used is
    /// closed, or when the client had no transport to close. No clock bounds
    /// this wait. Thus a transport whose own `disconnect()` never returns
    /// makes this method, and the next connect attempt, wait for it. Such a
    /// transport has a defect. The built-in stdio and in-memory transports
    /// return from `disconnect()`.
    ///
    /// A connect attempt that started before this call and still runs is
    /// ended too. This method first stops the message loop of the client of
    /// each such attempt: it starts the teardown of that client, and waits
    /// until the teardown returned or the transport closed. Then it calls the
    /// `disconnect()` of the transport of the attempt itself, also when the
    /// `connect()` of that transport did not return, and waits until the
    /// transport closed. For an attempt whose factory did not return yet,
    /// this method waits until the factory returned: the attempt is stale,
    /// thus it releases that transport at once and never connects it. Thus
    /// no transport and no stdio subprocess of this server stays or appears
    /// after this method returns.
    ///
    /// A factory that never returns makes this method wait for it. Such a
    /// factory has a defect, the same as a transport whose `disconnect()`
    /// never returns.
    public func disconnect() async {
        await cancellationNotices.drain()
        connectGeneration += 1
        let teardownGeneration = connectGeneration
        coalescingTask?.cancel()
        failInFlightCalls(underlying: Self.hostDisconnectedDescription)
        // The teardown of the current client starts here. `endAttempts`
        // waits until that teardown stopped the message loop of the client,
        // and only then closes the transport of the client itself.
        if let retired = currentClient {
            dropAttemptClient(retired)
        }
        await endAttempts(before: teardownGeneration)
        transition(to: .disconnected)
    }

    // MARK: - The retry loop

    /// Makes one attempt inside the retry loop, logs its result, and decides
    /// whether the loop retries, gives up, or returns.
    ///
    /// - Parameters:
    ///   - factory: Builds the fresh transport to connect over.
    ///   - attempt: The 1-based number of this attempt.
    ///   - policy: The policy of the loop.
    /// - Returns: What the loop does next.
    private func attemptConnectionWithLogging(
        factory: @escaping TransportFactory, attempt: Int, policy: BackoffPolicy
    ) async -> ConnectAttemptOutcome {
        do {
            try await performConnectAttempt(factory: factory, timeout: policy.connectTimeout)
            record(
                .mcpConnectAttemptSucceeded, level: .info,
                metadata: Self.attemptMetadata(attempt, policy: policy))
            return .connected
        } catch {
            return failedAttemptOutcome(error, attempt: attempt, policy: policy)
        }
    }

    /// Classifies the failure of one attempt: permanent, exhausted, or a
    /// retry after the backoff delay — and logs each.
    ///
    /// - Parameters:
    ///   - error: What the attempt threw.
    ///   - attempt: The 1-based number of the attempt that failed.
    ///   - policy: The policy of the loop.
    /// - Returns: What the loop does next.
    private func failedAttemptOutcome(
        _ error: any Error, attempt: Int, policy: BackoffPolicy
    ) -> ConnectAttemptOutcome {
        let failure = Self.attemptMetadata(attempt, policy: policy)
            .merging(MultitoolTelemetry.errorMetadata(of: error)) { attemptValue, _ in attemptValue }
        if let nonRetryable = error as? NonRetryableConnectError, nonRetryable.isNonRetryable {
            record(.mcpConnectAttemptRefused, level: .error, metadata: failure)
            return .permanentFailure(error)
        }
        record(.mcpConnectAttemptFailed, level: .warning, metadata: failure)
        guard attempt < policy.maxAttempts else { return .exhausted(error) }
        let delay = Self.backoffDelay(afterAttempt: attempt, policy: policy)
        record(
            .mcpConnectRetryScheduled, level: .info,
            metadata: MultitoolTelemetry.durationMetadata(of: delay))
        return .retryAfter(delay)
    }

    /// The metadata of the attempt limit of `policy`.
    ///
    /// - Parameter policy: The policy of the retry loop.
    /// - Returns: `policy.maxAttempts` under
    ///   `MultitoolTelemetry.LogMetadataKey.connectAttemptLimit`.
    private static func attemptLimitMetadata(_ policy: BackoffPolicy) -> Logger.Metadata {
        [MultitoolTelemetry.LogMetadataKey.connectAttemptLimit.rawValue: "\(policy.maxAttempts)"]
    }

    /// The metadata of one attempt of the retry loop: its number and the
    /// attempt limit of `policy`.
    ///
    /// - Parameters:
    ///   - attempt: The 1-based number of the attempt.
    ///   - policy: The policy of the retry loop.
    /// - Returns: The number under
    ///   `MultitoolTelemetry.LogMetadataKey.connectAttempt`, and the limit.
    private static func attemptMetadata(_ attempt: Int, policy: BackoffPolicy) -> Logger.Metadata {
        var metadata = attemptLimitMetadata(policy)
        metadata[MultitoolTelemetry.LogMetadataKey.connectAttempt.rawValue] = "\(attempt)"
        return metadata
    }

    /// The exponential backoff delay for the retry after `attempt`.
    ///
    /// - Parameters:
    ///   - attempt: The 1-based attempt number that just failed.
    ///   - policy: The policy that supplies `baseDelay` and `maxDelay`.
    /// - Returns: `baseDelay * 2^(attempt - 1)`, capped at `maxDelay` — the
    ///   delay after the first failure is `baseDelay`, after the second
    ///   `baseDelay * 2`, after the third `baseDelay * 4`, and so on.
    private static func backoffDelay(afterAttempt attempt: Int, policy: BackoffPolicy) -> Duration {
        var delay = policy.baseDelay
        for _ in 1..<attempt {
            delay = delay * Self.exponentialBackoffMultiplier
        }
        return min(delay, policy.maxDelay)
    }

    // MARK: - One attempt

    /// Makes one connect attempt bounded by `timeout` on
    /// ``connectAttemptClock`` — the real clock for a host — and never on
    /// ``clock``, which is for the delay BETWEEN attempts.
    ///
    /// See the header of this file for why this races two un-joined tasks
    /// instead of a task group. `factory` runs inside the same race as the
    /// handshake it feeds: a factory that spawns a subprocess and hangs is as
    /// bounded by `timeout` as a transport whose own `connect()` hangs.
    ///
    /// The current client is torn down before the race, and the race starts
    /// only after its transport closed. An earlier attempt that still runs
    /// is not waited for: it has its own client.
    ///
    /// - Parameters:
    ///   - factory: Builds the fresh transport to connect over.
    ///   - timeout: The maximum real wall-clock time this attempt may take.
    /// - Throws: What `factory` or the handshake throws, or
    ///   ``MCPServerError/connectAttemptTimedOut`` when `timeout` elapses
    ///   first.
    private func performConnectAttempt(
        factory: @escaping TransportFactory, timeout: Duration
    ) async throws {
        recordConnectStart()
        connectGeneration += 1
        let generation = connectGeneration
        await retireCurrentClient()

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            let resume = SingleResume(continuation)
            Task {
                await self.applyConnectResuming(
                    factory: factory, generation: generation, resume: resume)
            }
            Task { await self.failConnectAttemptAfterTimeout(timeout, resume: resume) }
        }
    }

    /// One side of the race of `performConnectAttempt(factory:timeout:)`:
    /// makes the attempt and resumes `resume` with its outcome.
    ///
    /// - Parameters:
    ///   - factory: Builds the fresh transport to connect over.
    ///   - generation: The ``connectGeneration`` this attempt was launched
    ///     under.
    ///   - resume: The shared resumption both sides resume at most one time.
    private func applyConnectResuming(
        factory: @escaping TransportFactory, generation: Int,
        resume: SingleResume<Void, any Error>
    ) async {
        do {
            try await applyConnect(via: factory, generation: generation)
            resume.resume(with: .success(()))
        } catch {
            resume.resume(with: .failure(error))
        }
    }

    /// The other side of the race: sleeps for `timeout` on
    /// ``connectAttemptClock``, then resumes `resume` with
    /// ``MCPServerError/connectAttemptTimedOut`` — a no-op when the attempt
    /// already won.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait before this attempt is timed out.
    ///   - resume: The shared resumption both sides resume at most one time.
    private func failConnectAttemptAfterTimeout(
        _ timeout: Duration, resume: SingleResume<Void, any Error>
    ) async {
        try? await connectAttemptClock.sleep(for: timeout)
        resume.resume(with: .failure(MCPServerError.connectAttemptTimedOut))
    }

    /// The connection work shared by the single-attempt and the retried
    /// connects: calls `factory` for a fresh transport, makes a new client
    /// and connects it over that transport, then discovers every tool through
    /// the paginated `tools/list` — and mutates ``state``, ``identity``,
    /// ``currentClient`` and ``discoveredTools`` only when `generation` still
    /// matches ``connectGeneration`` at the moment it would apply its result.
    /// A success and a failure after a prior success each emit one
    /// ``catalogUpdates`` snapshot.
    ///
    /// A fresh, non-racing `connect(via:)` always passes its own
    /// just-incremented generation, so the guard is satisfied there. For an
    /// abandoned attempt that lost its race against `connectTimeout` and
    /// finishes later, a newer attempt (or the loop giving up) moved the
    /// generation on, so the stale result is logged and discarded, and the
    /// attempt tears its own client down: it is never installed, and its
    /// transport closes.
    ///
    /// A failed attempt whose generation is still current tears its client
    /// down and waits until its transport closed, and only then throws. Thus
    /// the next attempt of the retry loop spawns its transport only after
    /// the transport of the failed attempt closed.
    ///
    /// - Parameters:
    ///   - factory: Builds the fresh transport to connect over.
    ///   - generation: The ``connectGeneration`` this attempt was launched
    ///     under.
    /// - Throws: What `factory`, `MCP.Client.connect(transport:)` or
    ///   `discoverAllTools(on:)` throws — even when `generation` turns out to
    ///   be stale, so the detached task of
    ///   `performConnectAttempt(factory:timeout:)` still observes failure
    ///   against success correctly.
    private func applyConnect(via factory: TransportFactory, generation: Int) async throws {
        guard
            isCurrentGeneration(
                generation, orDiscard: .mcpStaleAttemptSkipped)
        else {
            return
        }
        transition(to: .connecting)
        // The attempt is in the set before its factory runs, thus a teardown
        // that starts now waits until the factory returned.
        let transportID = beginAttempt(generation: generation)
        var attempt: AttemptClient?
        do {
            let transport: any Transport
            do {
                transport = try await factory()
            } catch {
                closeOpenTransport(transportID)
                throw error
            }
            guard
                let made = await makeAttemptClient(
                    over: transport, transportID: transportID, generation: generation)
            else {
                return
            }
            attempt = made
            let initialized = try await made.client.connect(transport: made.transport)
            guard isCurrentGeneration(generation, orDiscard: .mcpStaleSuccessDiscarded) else {
                dropAttemptClient(made)
                return
            }
            // A fresh connection: the drop of the previous one, if any, is
            // over. Cleared before discovery, so a drop under discovery is
            // recorded against this connection and not lost to the reset.
            currentClient = made
            isTransportDropped = false
            let tools = try await discoverAllTools(on: made.client)
            guard isCurrentGeneration(generation, orDiscard: .mcpStaleSuccessDiscarded) else {
                dropAttemptClient(made)
                return
            }
            discoveredTools = tools
            establishIdentityIfAbsent()
            transition(to: .ready)
            emitCatalogSnapshot()
            record(
                .mcpServerInitialized, level: .debug,
                metadata: [
                    MultitoolTelemetry.LogMetadataKey.peerServerName.rawValue: "\(initialized.serverInfo.name)",
                    MultitoolTelemetry.LogMetadataKey.itemCount.rawValue: "\(tools.count)",
                ])
        } catch {
            guard
                isCurrentGeneration(
                    generation,
                    orDiscard: .mcpStaleFailureDiscarded,
                    error: error)
            else {
                if let attempt {
                    dropAttemptClient(attempt)
                }
                throw error
            }
            if let attempt {
                dropAttemptClient(attempt)
                await waitUntilTransportClosed(attempt.transportID)
            }
            transition(to: .faulted(String(describing: error)))
            emitCatalogSnapshot()
            throw error
        }
    }

    /// Reports whether `generation` still matches ``connectGeneration``, and
    /// logs the discard otherwise — the one comparison behind every "stale
    /// generation" guard of a connect attempt.
    ///
    /// - Parameters:
    ///   - generation: The ``connectGeneration`` the attempt was launched
    ///     under.
    ///   - message: The constant message of the record that names what the
    ///     caller discards when the generation is stale.
    ///   - error: The error being discarded, when there is one. The record
    ///     holds its type and its code only.
    /// - Returns: `true` when `generation` is current and the caller
    ///   proceeds; `false` when it was logged and discarded as stale.
    func isCurrentGeneration(
        _ generation: Int, orDiscard message: MultitoolTelemetry.LogMessage, error: (any Error)? = nil
    ) -> Bool {
        guard generation == connectGeneration else {
            record(message, level: .warning, metadata: error.map(MultitoolTelemetry.errorMetadata(of:)) ?? [:])
            return false
        }
        return true
    }

    // MARK: - The handlers registered on each new client

    /// Registers every handler this actor needs on `client`, a new client of
    /// one connect attempt, before its connect.
    ///
    /// Each attempt makes its own client, thus each registration runs one
    /// time for each client: `MCP.Client.onNotification(_:handler:)` appends
    /// a handler to the list of the client, and that list starts empty.
    ///
    /// The client gets no handler for `notifications/elicitation/complete`.
    /// The `DropObservingTransport` of the attempt relays that notification
    /// before the client loop reads it, thus one completion makes one
    /// record — see `makeAttemptClient(over:transportID:generation:)`.
    ///
    /// - Parameter client: The new client of the attempt.
    func setupHandlers(on client: MCP.Client) async {
        await registerNotificationHandler(ToolListChangedNotification.self, on: client) { server, _ in
            await server.handleToolListChangedNotification()
        }
        await registerNotificationHandler(ProgressNotification.self, on: client) { server, message in
            await server.handleProgressNotification(parameters: message.params)
        }
        await registerElicitationHandler(on: client)
    }

    /// Registers `client.onNotification(_:handler:)` for `type`, guarding
    /// against `self` having been deallocated by the time a notification
    /// arrives.
    ///
    /// - Parameters:
    ///   - type: The notification type to register a handler for.
    ///   - client: The client to register the handler on.
    ///   - handler: Invoked with `self` and the received message once `self`
    ///     is confirmed still alive.
    private func registerNotificationHandler<N: Notification>(
        _ type: N.Type, on client: MCP.Client,
        handler: @escaping @Sendable (MCPServer, Message<N>) async -> Void
    ) async {
        await client.onNotification(type) { [weak self] message in
            guard let self else { return }
            await handler(self, message)
        }
    }
}
