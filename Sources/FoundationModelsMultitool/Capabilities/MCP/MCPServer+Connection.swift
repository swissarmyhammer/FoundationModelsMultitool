// `MCPServer+Connection` — connect, disconnect, reconnect, and the backoff
// retry loop of one `MCPServer`.
//
// A behavioral port of `connect(via:)` in its four forms, `disconnect()`,
// `reconnectAfterFault()`, `performConnectAttempt(factory:timeout:)`,
// `applyConnect(via:generation:)`, `setupHandlers()` and the helpers of each
// of them, of `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`.
//
// **What `reconnect()` is.** The source reconnected from inside the call path,
// when a mid-call transport fault was noticed. That call path is not ported.
// The reconnect itself — call the retained factory again, under the retained
// policy — is a host operation here, `reconnect()`, and the later task that
// rewrites the call path onto the run plane calls it on a fault.
//
// **What `setupHandlers()` registers.** The source registered three
// notification handlers: `tools/list_changed`, `progress` and
// `elicitation/complete`. The `progress` handler belongs to the deleted call
// path and is gone for good. The `elicitation/complete` handler comes with the
// elicitation task. The `tools/list_changed` handler is registered here, once
// per actor, and routes to the coalesced re-list of
// `MCPServer+LiveCatalog.swift`.
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
// the loser keeps running and its late result is discarded by the generation
// guard.

import MCP
import os

extension MCPServer {
    /// The base of the exponential backoff of `backoffDelay(afterAttempt:policy:)`
    /// — each failed attempt doubles the prior delay.
    private static let exponentialBackoffMultiplier = 2.0

    /// The key `registerNotificationHandlerOnce(_:register:)` records the
    /// `tools/list_changed` registration under.
    private static let toolListChangedHandlerName = "toolListChanged"

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
        // `MCP.Client.connect(transport:)` never cancels the message-handling
        // task of a previous call before it starts a new one, so a reconnect
        // without a disconnect first leaves two tasks racing to consume the
        // same receive stream. `disconnect()` is a no-op before any
        // connection was ever made.
        await disconnectClientWithoutHanging()
        connectGeneration += 1
        try await applyConnect(via: factory, generation: connectGeneration)
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
        logger.error(
            "MCPServer \(self.identityNameForDiagnostics, privacy: .public) exhausted its connect backoff after \(backoffPolicy.maxAttempts) attempts: \(String(describing: lastError), privacy: .public)"
        )
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
        logger.info("MCPServer \(self.identityNameForDiagnostics, privacy: .public) reconnected")
    }

    /// Disconnects the client and moves ``state`` to `.disconnected`, without
    /// altering ``identity``.
    ///
    /// Bumps the generation, so a connect attempt still in flight when this
    /// runs is discarded instead of moving the state back to `.ready`, and
    /// cancels a `tools/list_changed` watcher still waiting out its coalesce
    /// window, so it re-lists nothing against the disconnected client. A
    /// later `connect(via:)` is what drives the next transition.
    public func disconnect() async {
        connectGeneration += 1
        coalescingTask?.cancel()
        await disconnectClientWithoutHanging()
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
            logger.info(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) connected on attempt \(attempt)"
            )
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
        let description = String(describing: error)
        if let nonRetryable = error as? NonRetryableConnectError, nonRetryable.isNonRetryable {
            logger.error(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) connect attempt \(attempt) failed with a non-retryable configuration error; not retrying: \(description, privacy: .public)"
            )
            return .permanentFailure(error)
        }
        logger.warning(
            "MCPServer \(self.identityNameForDiagnostics, privacy: .public) connect attempt \(attempt) of \(policy.maxAttempts) failed: \(description, privacy: .public)"
        )
        guard attempt < policy.maxAttempts else { return .exhausted(error) }
        let delay = Self.backoffDelay(afterAttempt: attempt, policy: policy)
        logger.info(
            "MCPServer \(self.identityNameForDiagnostics, privacy: .public) backs off \(String(describing: delay), privacy: .public) before the next connect retry"
        )
        return .retryAfter(delay)
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

    /// Makes one connect attempt bounded by `timeout` in real wall-clock time
    /// — never the injected clock, which is for the delay BETWEEN attempts.
    ///
    /// See the header of this file for why this races two un-joined tasks
    /// instead of a task group. `factory` runs inside the same race as the
    /// handshake it feeds: a factory that spawns a subprocess and hangs is as
    /// bounded by `timeout` as a transport whose own `connect()` hangs.
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
        await disconnectClientWithoutHanging()
        connectGeneration += 1
        let generation = connectGeneration

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

    /// The other side of the race: sleeps for `timeout`, then resumes
    /// `resume` with ``MCPServerError/connectAttemptTimedOut`` — a no-op when
    /// the attempt already won.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait before this attempt is timed out.
    ///   - resume: The shared resumption both sides resume at most one time.
    private func failConnectAttemptAfterTimeout(
        _ timeout: Duration, resume: SingleResume<Void, any Error>
    ) async {
        try? await Task.sleep(for: timeout)
        resume.resume(with: .failure(MCPServerError.connectAttemptTimedOut))
    }

    /// The connection work shared by the single-attempt and the retried
    /// connects: calls `factory` for a fresh transport, connects over it,
    /// then discovers every tool through the paginated `tools/list` — and
    /// mutates ``state``, ``identity`` and ``discoveredTools`` only when
    /// `generation` still matches ``connectGeneration`` at the moment it
    /// would apply its result. A success and a failure after a prior success
    /// each emit one ``catalogUpdates`` snapshot.
    ///
    /// A fresh, non-racing `connect(via:)` always passes its own
    /// just-incremented generation, so the guard is satisfied there. For an
    /// abandoned attempt that lost its race against `connectTimeout` and
    /// finishes later, a newer attempt (or the loop giving up) moved the
    /// generation on, so the stale result is logged and discarded.
    ///
    /// - Parameters:
    ///   - factory: Builds the fresh transport to connect over.
    ///   - generation: The ``connectGeneration`` this attempt was launched
    ///     under.
    /// - Throws: What `factory`, `MCP.Client.connect(transport:)` or
    ///   `discoverAllTools()` throws — even when `generation` turns out to be
    ///   stale, so the detached task of
    ///   `performConnectAttempt(factory:timeout:)` still observes failure
    ///   against success correctly.
    private func applyConnect(via factory: TransportFactory, generation: Int) async throws {
        guard
            isCurrentGeneration(
                generation, orDiscard: "skipping a connect attempt a newer one superseded")
        else {
            return
        }
        transition(to: .connecting)
        await setupHandlers()
        do {
            let transport = try await factory()
            guard
                let initialized = try await connectClientExclusively(
                    transport: transport, generation: generation)
            else {
                return
            }
            let tools = try await discoverAllTools()
            guard
                isCurrentGeneration(
                    generation,
                    orDiscard: "discarding a stale connect success; a newer attempt started")
            else {
                return
            }
            discoveredTools = tools
            establishIdentityIfAbsent()
            transition(to: .ready)
            emitCatalogSnapshot()
            logger.debug(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) initialized against server \(initialized.serverInfo.name, privacy: .public) with \(tools.count) tools"
            )
        } catch {
            guard
                isCurrentGeneration(
                    generation,
                    orDiscard: "discarding a stale connect failure; a newer attempt started",
                    error: error)
            else {
                throw error
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
    ///   - message: What the caller discards when the generation is stale.
    ///   - error: The error being discarded, when there is one.
    /// - Returns: `true` when `generation` is current and the caller
    ///   proceeds; `false` when it was logged and discarded as stale.
    func isCurrentGeneration(
        _ generation: Int, orDiscard message: String, error: (any Error)? = nil
    ) -> Bool {
        guard generation == connectGeneration else {
            let errorDescription = error.map { String(describing: $0) } ?? "none"
            logger.warning(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) \(message, privacy: .public) (error: \(errorDescription, privacy: .public))"
            )
            return false
        }
        return true
    }

    // MARK: - The notification handlers registered at connect

    /// Registers every notification handler this actor needs on ``client`` —
    /// extracted from `applyConnect(via:generation:)` so that method reads as
    /// "register handlers, then connect".
    ///
    /// `MCP.Client.onNotification(_:handler:)` appends a handler to its list
    /// instead of replacing it, so each registration goes through
    /// `registerNotificationHandlerOnce(_:register:)` and runs at most one
    /// time per actor, however many reconnects follow.
    private func setupHandlers() async {
        await registerNotificationHandlerOnce(Self.toolListChangedHandlerName) {
            await self.registerNotificationHandler(ToolListChangedNotification.self) { server, _ in
                await server.handleToolListChangedNotification()
            }
        }
    }

    /// Runs `register` at most one time per actor, keyed by `name`.
    ///
    /// - Parameters:
    ///   - name: A stable key for the handler, recorded in
    ///     ``registeredNotificationHandlers`` before `register` runs.
    ///   - register: The registration, invoked the first time `name` is seen.
    private func registerNotificationHandlerOnce(
        _ name: String, register: () async -> Void
    ) async {
        guard !registeredNotificationHandlers.contains(name) else { return }
        registeredNotificationHandlers.insert(name)
        await register()
    }

    /// Registers `client.onNotification(_:handler:)` for `type`, guarding
    /// against `self` having been deallocated by the time a notification
    /// arrives.
    ///
    /// - Parameters:
    ///   - type: The notification type to register a handler for.
    ///   - handler: Invoked with `self` and the received message once `self`
    ///     is confirmed still alive.
    private func registerNotificationHandler<N: Notification>(
        _ type: N.Type, handler: @escaping @Sendable (MCPServer, Message<N>) async -> Void
    ) async {
        await client.onNotification(type) { [weak self] message in
            guard let self else { return }
            await handler(self, message)
        }
    }
}
