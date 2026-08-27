// `MCPServer` — one `MCP.Client` connection to one MCP server: the actor, its
// state, and the readiness a host waits on.
//
// A behavioral port of the connection and discovery halves of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`, split
// across five files by concern, the way `RoutedSessionActor*.swift` splits
// its actor in Router:
//
// - `MCPServer.swift` (this file) — the actor: its stored state, `init`,
//   `waitUntilReady()`, and the one funnel every state change goes through.
// - `MCPServer+Connection.swift` — `connect(via:)` in its four forms,
//   `disconnect()`, `reconnect()`, the backoff retry loop, the generation
//   guard, and the notification handlers registered at connect.
// - `MCPServer+ClientQueue.swift` — the FIFO queue that serializes every
//   `client.connect(transport:)` and `client.disconnect()` call.
// - `MCPServer+Discovery.swift` — the paginated `tools/list` round trip a
//   connect makes, `mcpTools()`, `tool(named:)`, `catalog`, and the one
//   emission point of `catalogUpdates`.
// - `MCPServer+LiveCatalog.swift` — the coalesced re-list a burst of
//   `tools/list_changed` notifications starts.
// - `MCPServer+Call.swift` — `call(name:arguments:)`, the one call method,
//   on the run plane of Router: the in-flight table, progress to the ambient
//   `ToolContext`, cancellation to the wire, and the transport drop as
//   `MCPServerError.lost`. `DropObservingTransport.swift` is the transport
//   the client connects over, which reports that drop.
//
// **What is not ported, for good.** The call path of the source — the soft
// deadline, the call handle and the running-call snapshot, the retained call
// records, the three follow-up tools, the progress and outcome streams — is
// gone. eventplan.md § "Consolidation of the siblings": "We delete
// the two local designs." The call path stands on the run plane of Router
// instead — see `MCPServer+Call.swift`. A discovered tool is an
// `MCPCatalogEntry` here, and `mcpTools()` and `tool(named:)` vend that
// entry; `MCPTool.swift` is the plain `Tool` a host builds over one entry.
//
// **This actor constructs its own `MCP.Client`.** In swift-sdk 0.12.1 the
// client capabilities are fixed at `Client.init(name:version:capabilities:)`
// and sent verbatim in `initialize`; nothing can add one at connect. And
// `Client.Capabilities.Elicitation.init(form:url:)` defaults `url` to `nil`,
// so URL-mode elicitation is off unless declared. So `init` builds the client
// with `Elicitation(form: .init(), url: .init())`, and takes no client from
// the host. The elicitation handler registration comes with the elicitation
// task; the capability is declared here, because the declaration cannot wait
// for the handler.
//
// **Logging goes through `os.Logger`**, as `MultiTool.swift` logs. Each
// message names the server, so a stream can be narrowed to one connection.

import MCP
import os

/// Owns one `MCP.Client` connection to a single MCP server: the async
/// `connect(via:)` handshake, a `connecting` / `ready` / `disconnected` /
/// `faulted` readiness state machine, and a stable ``ServerIdentity`` that
/// survives reconnects.
///
/// `MCP.Client` is a concrete `actor` of the swift-sdk with its own connection
/// and request internals; `MCPServer` wraps it directly, because this actor
/// owns the whole lifecycle of the client — connect, reconnect, disconnect.
/// The host supplies the `Transport` (in-memory, stdio, HTTP) through
/// `connect(via:)` — either an already-constructed instance, or, for a
/// transport that must be freshly built on every reconnect attempt (a stdio
/// transport whose subprocess must be freshly spawned), a ``TransportFactory``
/// this actor calls on demand.
///
/// `public`, because a host constructs and connects a server before
/// `buildRegistry()`; the capability that registers the tools of a connected
/// server comes in a later task.
public actor MCPServer {
    /// The version ``init(name:version:clock:callTimeout:renderBudget:logger:)``
    /// reports at `initialize` when the host names none.
    public static let defaultClientVersion = "1.0"

    /// How many seconds ``defaultCallTimeout`` lasts.
    private static let defaultCallTimeoutSeconds = 120

    /// The default ``callTimeout`` — see that property.
    public static let defaultCallTimeout = Duration.seconds(defaultCallTimeoutSeconds)

    /// The logger ``init(name:version:clock:callTimeout:renderBudget:logger:)``
    /// takes when the host supplies none.
    public static let defaultLogger = Logger(
        subsystem: "FoundationModelsMultitool", category: "MCPServer")

    /// The wrapped swift-sdk client this actor owns for its whole lifetime.
    ///
    /// Internal, not private: a test reads the capabilities the client sends
    /// at `initialize` through `@testable import`. Nothing else in this
    /// package reaches it — every connect and disconnect goes through this
    /// actor.
    let client: MCP.Client

    /// The name of this connection: the client name sent at `initialize`, and
    /// the ``identity`` once the first connect succeeds.
    public let name: String

    /// The render budget every rendered result of this server obeys — see
    /// `RenderBudget`. Stored at construction for `MCPTool`, the verb that
    /// renders a `CallTool.Result` for the model.
    public let renderBudget: RenderBudget

    /// The bound of a call made with no ambient `ToolContext` — a bare host
    /// call, outside any run of Router — measured from the moment the
    /// request went out, and reset by nothing. Once it elapses, the call
    /// answers an in-band `isError` result and `notifications/cancelled` goes
    /// out for the request. Defaults to ``defaultCallTimeout``.
    ///
    /// A call made under a context is never bounded by this: the engine's
    /// `timeout` is its clock, and every `notifications/progress` resets it.
    /// See `MCPServer+Call.swift`.
    public let callTimeout: Duration

    /// The current readiness state — see ``MCPServerState``.
    public private(set) var state: MCPServerState = .connecting

    /// This server's stable identity, established once the first
    /// `connect(via:)` call succeeds, and never recomputed afterward.
    ///
    /// `nil` until then, and still `nil` after a first connect that fails, so
    /// ``identity`` and ``state`` never disagree about whether a connection
    /// ever succeeded.
    public private(set) var identity: ServerIdentity?

    /// The clock `connect(via:backoffPolicy:)` sleeps on between retry
    /// attempts — injectable so a test substitutes a virtual clock and drives
    /// a full backoff schedule with no real delay.
    let clock: any Clock<Duration>

    /// The logger every retry, reconnect and discarded attempt is reported to.
    let logger: Logger

    /// The ``TransportFactory`` of the most recent `connect(via:)` call,
    /// successful or not, retained so that ``reconnect()`` can call it again
    /// for a FRESH transport — without the host supplying anything a second
    /// time.
    ///
    /// - Important: The single-transport-instance `connect(via:)` overloads
    ///   store `{ transport }` here — a factory that always returns that same
    ///   instance. A reconnect through it retries that exact instance: safe
    ///   for a transport that re-establishes itself when reused (an HTTP
    ///   transport that redials on `connect()`), and useless for one that
    ///   wraps an already-severed connection, above all a stdio transport
    ///   over a dead subprocess. Pass a factory to `connect(via:)` for a
    ///   transport that must be freshly constructed on every attempt.
    var transportFactory: TransportFactory?

    /// Incremented at the start of every connect attempt, and captured by
    /// that attempt as the generation it must still match before it mutates
    /// ``state`` or ``identity`` — see `performConnectAttempt(factory:timeout:)`
    /// for why an abandoned, still-running attempt can otherwise resolve long
    /// after the retry loop moved on. `disconnect()` increments it too, so no
    /// straggler moves a disconnected server back to `.ready`.
    var connectGeneration = 0

    /// The backoff policy `connect(via:backoffPolicy:)` was last called with,
    /// reused by ``reconnect()`` — a server reconnects with the same policy it
    /// last connected with. A server that only ever called the single-attempt
    /// `connect(via:)` reconnects with ``BackoffPolicy/default``.
    var activeBackoffPolicy: BackoffPolicy = .default

    /// The tail of the FIFO queue that serializes every operation this actor
    /// issues against ``client`` that mutates its internal connection state —
    /// `client.connect(transport:)` and `client.disconnect()` — see
    /// `enqueueClientOperation(kind:_:)` in `MCPServer+ClientQueue.swift`.
    ///
    /// Starts as an already-completed sentinel task, so the first operation
    /// ever enqueued has nothing to wait for.
    var clientQueueTail: Task<Void, Never> = Task {}

    /// The number of enqueued connect operations whose real
    /// `client.connect(transport:)` call has not yet finished — see
    /// `enqueueClientOperation(kind:_:)` for the bound this selects.
    var pendingConnectStragglers = 0

    /// The names of the notification handlers already registered on
    /// ``client`` — `MCP.Client.onNotification(_:handler:)` appends a handler
    /// to its list instead of replacing it, so each registration runs at most
    /// one time per actor however many reconnects follow.
    var registeredNotificationHandlers: Set<String> = []

    /// Every ``waitUntilReady()`` caller suspended on a state that is still
    /// `.connecting`, resumed by the next state change.
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    /// The tools the most recent successful discovery round trip returned —
    /// the paginated `tools/list` of a connect, or the coalesced re-list a
    /// `tools/list_changed` burst starts — in `tools/list` page order.
    ///
    /// Replaced whole on every successful round trip, and left as it was by
    /// a round trip that failed. See `MCPServer+Discovery.swift`.
    var discoveredTools: [MCPCatalogEntry] = []

    /// Incremented by every `emitCatalogSnapshot()` call — the per-server
    /// generation number each ``catalogUpdates`` snapshot carries as
    /// `MCPToolCatalog.epoch`. Starts at `0`, before any successful connect,
    /// and is never reset for the life of this actor.
    var catalogEpoch = 0

    /// The stream of versioned `MCPToolCatalog` snapshots this server emits.
    ///
    /// `emitCatalogSnapshot()` in `MCPServer+Discovery.swift` is the one
    /// point that yields to it, and it runs at each of these moments:
    ///
    /// - A `connect(via:)` that reaches `.ready` — the first connect, and
    ///   every reconnect after it, whether through `reconnect()` or through a
    ///   new `connect(via:)` call. A consumer sees a reconnect the same way it
    ///   sees a `tools/list_changed`: one snapshot with the tools of the
    ///   returning server, which may differ from the tools before.
    /// - A connect after a prior success that fails — one snapshot whose state
    ///   is `.faulted`, with the last-known tools.
    /// - A coalesced `tools/list_changed` re-list that succeeds — see
    ///   `MCPServer+LiveCatalog.swift`.
    ///
    /// Every emission is a complete, self-contained snapshot a consumer can
    /// start from with no prior state — never a delta. No emission occurs
    /// before the first successful connect, because ``identity`` — which
    /// every snapshot carries — is not established before then, and
    /// `disconnect()` emits none: a host that disconnects on purpose knows.
    ///
    /// - Important: Backed by a single continuation, like any `AsyncStream`:
    ///   one consumer iterates this stream. A second concurrent iterator is a
    ///   programming error — it would only ever see whichever snapshots the
    ///   first one has not already consumed, never a copy of every snapshot.
    ///
    /// - Note: Finishes when this server is deallocated, and never before — a
    ///   connection fault emits a snapshot instead of ending the stream.
    let catalogUpdates: AsyncStream<MCPToolCatalog>

    /// The continuation `emitCatalogSnapshot()` yields new snapshots to —
    /// paired with ``catalogUpdates`` one time, at construction.
    let catalogContinuation: AsyncStream<MCPToolCatalog>.Continuation

    /// Incremented by every inbound `tools/list_changed` notification, and
    /// read back by the coalescing re-list to learn whether more arrived
    /// while it ran — see `coalesceAndRelist()` in
    /// `MCPServer+LiveCatalog.swift`.
    var toolListChangedGeneration = 0

    /// Whether a `coalesceAndRelist()` watcher is running, so a burst of
    /// notifications starts one watcher and not one per notification.
    var isCoalescingToolListChanged = false

    /// The task `handleToolListChangedNotification()` started to run
    /// `coalesceAndRelist()`, or `nil` when no watcher is running.
    ///
    /// Stored, so that `disconnect()` cancels a watcher still waiting out its
    /// coalesce window instead of letting it re-list against a client the
    /// host just disconnected; cleared back to `nil` by the watcher itself
    /// once it finishes.
    var coalescingTask: Task<Void, Never>?

    /// Every `tools/call` in flight, keyed by its request id — see
    /// `MCPServer+Call.swift`. An entry is added when a call starts, and
    /// removed when the call settles and its caller was resumed.
    var inFlightCalls: [ID: InFlightCall] = [:]

    /// Whether the receive stream of the connected transport ended without a
    /// `disconnect()` — set by `handleTransportDrop(generation:)`, and reset
    /// by the next connect that succeeds. While set, a call that would send a
    /// request throws `MCPServerError.lost` at once, because no answer can
    /// arrive.
    var isTransportDropped = false

    /// Creates a server that owns a fresh `MCP.Client` named `name`.
    ///
    /// The client declares the elicitation capability with both `form` and
    /// `url` — see the header of this file for why the declaration stands
    /// here and not at connect.
    ///
    /// - Parameters:
    ///   - name: The name of this connection — the client name sent at
    ///     `initialize`, and the ``identity`` once the first connect succeeds.
    ///   - version: The client version sent at `initialize`. Defaults to
    ///     ``defaultClientVersion``.
    ///   - clock: The clock `connect(via:backoffPolicy:)` sleeps on between
    ///     retries. Defaults to a real `ContinuousClock`; a test substitutes a
    ///     virtual clock to drive a full backoff schedule with no real delay.
    ///     Never used by the per-attempt timeout, which always measures real
    ///     wall-clock time — a virtual clock that never suspends would make
    ///     the timeout win at once against an attempt in flight.
    ///   - callTimeout: The bound of a call made with no ambient
    ///     `ToolContext` — see ``callTimeout``. Defaults to
    ///     ``defaultCallTimeout``.
    ///   - renderBudget: The render budget every rendered result of this
    ///     server obeys. Defaults to `RenderBudget.default`.
    ///   - logger: The logger every retry, reconnect and discarded attempt is
    ///     reported to. Defaults to ``defaultLogger``.
    public init(
        name: String,
        version: String = MCPServer.defaultClientVersion,
        clock: any Clock<Duration> = ContinuousClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default,
        logger: Logger = MCPServer.defaultLogger
    ) {
        self.name = name
        self.client = Client(
            name: name,
            version: version,
            capabilities: Client.Capabilities(elicitation: .init(form: .init(), url: .init()))
        )
        self.clock = clock
        self.callTimeout = callTimeout
        self.renderBudget = renderBudget
        self.logger = logger
        (self.catalogUpdates, self.catalogContinuation) = AsyncStream.makeStream()
    }

    /// Finishes ``catalogUpdates``, so a consumer still iterating it ends
    /// once this server is gone — the one point that finishes the stream.
    deinit {
        catalogContinuation.finish()
    }

    /// The name log lines and ``MCPServerError`` carry for this server — the
    /// established ``identity`` once there is one, and ``name`` before that.
    var identityNameForDiagnostics: String {
        identity?.name ?? name
    }

    /// Suspends until ``state`` is `.ready`, and throws when it cannot get
    /// there without a new connect.
    ///
    /// A host that started a connect in the background calls this before it
    /// reads the tools of the server. A server that is still `.connecting`
    /// holds the caller until the next state change and then decides again;
    /// a server that is `.faulted` or `.disconnected` throws at once, because
    /// only a new `connect(via:)` moves it.
    ///
    /// - Throws: ``MCPServerError/notReady(_:)`` carrying the state that
    ///   stopped the wait.
    public func waitUntilReady() async throws {
        while true {
            switch state {
            case .ready:
                return
            case .faulted, .disconnected:
                throw MCPServerError.notReady(state)
            case .connecting:
                await withCheckedContinuation { continuation in
                    readinessWaiters.append(continuation)
                }
            }
        }
    }

    /// The one funnel every state change goes through: sets ``state`` and
    /// wakes every ``waitUntilReady()`` caller, so each one reads the new
    /// state and decides again.
    ///
    /// - Parameter newState: The state to move to.
    func transition(to newState: MCPServerState) {
        state = newState
        let waiters = readinessWaiters
        readinessWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Records ``identity`` on the first successful connect, and leaves it
    /// alone on every later one.
    func establishIdentityIfAbsent() {
        if identity == nil {
            identity = ServerIdentity(name: name)
        }
    }
}
