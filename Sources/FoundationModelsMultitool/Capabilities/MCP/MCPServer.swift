// `MCPServer` — one `MCP.Client` connection to one MCP server: the actor, its
// state, and the readiness a host waits on.
//
// A behavioral port of the connection and discovery halves of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`, split
// across five files by concern, the way Router splits the files of its
// session actor:
//
// - `MCPServer.swift` (this file) — the actor: its stored state, `init`,
//   `waitUntilReady()`, and the one funnel every state change goes through.
// - `MCPServer+Connection.swift` — `connect(via:)` in its four forms,
//   `disconnect()`, `reconnect()`, the backoff retry loop, the generation
//   guard, and the notification handlers registered at connect.
// - `MCPServer+ClientLifecycle.swift` — the new `MCP.Client` of each connect
//   attempt, the install of the client of the current attempt, the teardown
//   of an old client, and the set of transports that did not close yet.
// - `MCPServer+Discovery.swift` — the paginated `tools/list` round trip a
//   connect makes, `mcpTools()`, `tool(named:)`, `catalog`, and the one
//   emission point of `catalogUpdates`.
// - `MCPServer+LiveCatalog.swift` — the coalesced re-list a burst of
//   `tools/list_changed` notifications starts.
// - `MCPServer+Call.swift` — `call(name:arguments:)`, the one call method,
//   on the run plane of FoundationModelsExtras: the in-flight table,
//   progress to the ambient `ToolContext`, cancellation to the wire, and
//   the transport drop as `MCPServerError.lost`.
//   `DropObservingTransport.swift` is the transport the client connects
//   over, which reports that drop.
// - `MCPServer+Elicitation.swift` — the passthrough of a server-initiated
//   `elicitation/create` to `ToolContext.elicit`, the host's handler for a
//   bare session, and the relay of `notifications/elicitation/complete`.
//
// **What is not ported, for good.** The call path of the source — the soft
// deadline, the call handle and the running-call snapshot, the retained call
// records, the three follow-up tools, the progress and outcome streams — is
// gone. eventplan.md § "Consolidation of the siblings": "We delete
// the two local designs." The call path stands on the run plane of
// FoundationModelsExtras instead — see `MCPServer+Call.swift`. A
// discovered tool is an `MCPCatalogEntry` here, and `mcpTools()` and
// `tool(named:)` vend that entry; `MCPTool.swift` is the plain `Tool` a
// host builds over one entry.
//
// **This actor constructs its own `MCP.Client`, a new one for each connect
// attempt.** In swift-sdk 0.12.1 the client capabilities are fixed at
// `Client.init(name:version:capabilities:)` and sent verbatim in
// `initialize`; nothing can add one at connect. And
// `Client.Capabilities.Elicitation.init(form:url:)` defaults `url` to `nil`,
// so URL-mode elicitation is off unless declared. So each client gets
// ``clientCapabilities(for:)`` of the ``userPresence`` of this actor. An
// interactive session gets `Elicitation(form: .init(), url: .init())`. A
// headless session gets no elicitation capability, because no person can
// answer a question. This actor takes no client from the host. The handler
// of `elicitation/create` stays registered in the two modes: a server that
// sends a request it did not get the capability for still gets an answer.
// The handlers are registered on each new client before its connect, by
// `setupHandlers(on:)` in `MCPServer+Connection.swift`. See
// `MCPServer+ClientLifecycle.swift` for why each attempt gets its own client.
//
// **Logging goes through swift-log**, as `MultiTool.swift` logs. Each record
// has a constant `MultitoolTelemetry.LogMessage` and the server name in its
// metadata, so a reader can find the records of one connection. A record
// never holds an MCP payload, a tool argument or a tool output: an error goes
// in as its type and its code only. See `record(_:level:metadata:)`.

import FoundationModelsExtras
import Logging
import MCP
import ULID

/// Owns one `MCP.Client` connection to a single MCP server: the async
/// `connect(via:)` handshake, a `connecting` / `ready` / `disconnected` /
/// `faulted` readiness state machine, and a stable ``ServerIdentity`` that
/// survives reconnects.
///
/// `MCP.Client` is a concrete `actor` of the swift-sdk with its own connection
/// and request internals; `MCPServer` makes a new one for each connect
/// attempt, because this actor owns the whole lifecycle of each client —
/// connect, reconnect, disconnect.
/// The host supplies the `Transport` (in-memory, stdio, HTTP) through
/// `connect(via:)` — either an already-constructed instance, or, for a
/// transport that must be freshly built on every reconnect attempt (a stdio
/// transport whose subprocess must be freshly spawned), a ``TransportFactory``
/// this actor calls on demand.
///
/// `public`, because a host constructs and connects a server before
/// `buildRegistry()`; `MCPCapability` then registers the tools of the
/// connected server, through `MultiTool.Builder.withMCP(servers:)`.
public actor MCPServer {
    /// The version ``init(name:version:clock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``
    /// reports at `initialize` when the host names none.
    public static let defaultClientVersion = "1.0"

    /// How many seconds ``defaultCallTimeout`` lasts.
    private static let defaultCallTimeoutSeconds = 120

    /// The default ``callTimeout`` — see that property.
    public static let defaultCallTimeout = Duration.seconds(defaultCallTimeoutSeconds)

    /// The logger ``init(name:version:clock:callTimeout:renderBudget:elicitationHandler:userPresence:logger:)``
    /// takes when the host supplies none: the swift-log logger of the library.
    ///
    /// A new logger for each read, not a stored value: a logger keeps the
    /// handler of the logging system at the time it is made, and a host can
    /// bootstrap the logging system after this type loads.
    public static var defaultLogger: Logger {
        MultitoolTelemetry.logger
    }

    /// The capabilities each client of this actor sends at `initialize` —
    /// see the header of this file.
    ///
    /// An interactive session declares the elicitation capability with both
    /// `form` and `url`. A headless session declares no elicitation
    /// capability: no person can answer a question, thus a server must not
    /// send one.
    ///
    /// - Parameter presence: Whether a person is present to answer an
    ///   elicitation in this session.
    /// - Returns: The capabilities of a new client.
    static func clientCapabilities(for presence: UserPresence) -> Client.Capabilities {
        switch presence {
        case .interactive:
            return .init(elicitation: .init(form: .init(), url: .init()))
        case .headless:
            return .init()
        }
    }

    /// The client version each client of this actor sends at `initialize`.
    let clientVersion: String

    /// The client of the current connection, or `nil` when there is none —
    /// see `MCPServer+ClientLifecycle.swift`.
    ///
    /// Only the connect attempt whose generation is still current sets it,
    /// after its `initialize` handshake succeeded. A new attempt and
    /// `disconnect()` take it out, and tear its client down.
    var currentClient: AttemptClient?

    /// The client of the current connection, or `nil` when there is none.
    ///
    /// Internal, not private: a test reads the capabilities the client sends
    /// at `initialize` through `@testable import`. Each operation of this
    /// actor reads it one time, at its start, and uses that same client to
    /// its end.
    var client: MCP.Client? {
        currentClient?.client
    }

    /// Each connect attempt whose transport did not close yet, by its id —
    /// see `MCPServer+ClientLifecycle.swift`. An attempt goes in when it
    /// starts, before its factory runs, and adds its transport when the
    /// factory gave it. The close of the transport takes the attempt out, and
    /// so does the end of an attempt with no transport to close.
    /// `disconnect()` ends each attempt of an earlier generation and waits
    /// until none stays here.
    var openTransports: [Int: OpenTransport] = [:]

    /// The id the next attempt of ``openTransports`` gets.
    var nextTransportID = 0

    /// Each caller of `waitUntilTransportCloseIsAwaited()`, by the id of its
    /// wait — resumed when a caller starts to wait for the close of an open
    /// attempt, or when the task of the wait is cancelled. A test hook: no
    /// product code waits here.
    var transportCloseAwaitedWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    /// The id the next wait of ``transportCloseAwaitedWaiters`` gets.
    var nextTransportCloseAwaitedWaiterID = 0

    /// The name of this connection: the client name sent at `initialize`, and
    /// the ``identity`` once the first connect succeeds.
    public let name: String

    /// The render budget every rendered result of this server obeys — see
    /// `RenderBudget`. Stored at construction for `MCPTool`, the verb that
    /// renders a `CallTool.Result` for the model.
    public let renderBudget: RenderBudget

    /// The bound of a call made with no ambient `ToolContext` — a bare host
    /// call, outside any hosted run — measured from the moment the
    /// request went out, and reset by nothing. Once it elapses, the call
    /// answers an in-band `isError` result and `notifications/cancelled` goes
    /// out for the request. Defaults to ``defaultCallTimeout``.
    ///
    /// A call made under a context is never bounded by this: the engine's
    /// `timeout` is its clock, and every `notifications/progress` resets it.
    /// See `MCPServer+Call.swift`.
    public let callTimeout: Duration

    /// The host's answerer for a server-initiated elicitation that arrives
    /// under no `ToolContext` — the bare-session path. `nil` answers such a
    /// request with `cancel`. A Router host never sets it: a bound context
    /// answers first. See `MCPServer+Elicitation.swift`.
    let elicitationHandler: ElicitationHandler?

    /// Whether a person is present to answer an elicitation in this session.
    ///
    /// `.interactive` makes each client declare the elicitation capability.
    /// `.headless` makes each client declare no elicitation capability — see
    /// ``clientCapabilities(for:)`` — and answers each `elicitation/create`
    /// with `cancel` and `RunPlane.noUserPresentReason` at once. See
    /// `MCPServer+Elicitation.swift`.
    let userPresence: UserPresence

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

    /// The clock the per-attempt timeout of a connect sleeps on — see
    /// `failConnectAttemptAfterTimeout(_:resume:)` in
    /// `MCPServer+Connection.swift`.
    ///
    /// It is not ``clock``. A test gives ``clock`` a virtual clock whose sleep
    /// never waits, and a timeout that never waits would win at once against
    /// an attempt in flight. A host always gets the real clock here; a test of
    /// the timeout gives a clock it opens on command.
    let connectAttemptClock: any Clock<Duration>

    /// The clock the timer of a bare call sleeps on — see
    /// `startBareTimeout(for:)` in `MCPServer+Call.swift`.
    ///
    /// It is not ``clock``. A test gives ``clock`` a virtual clock whose sleep
    /// never waits, and a bare-call timer that never waits would end each bare
    /// call at once with the timeout result. A host always gets the real clock
    /// here; a test of the bare-call timeout gives a clock it controls.
    let callTimeoutClock: any Clock<Duration>

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

    /// Each caller of `waitUntilToolListChangedGeneration(reaches:)` that
    /// waits for a count of `tools/list_changed` notifications, with that
    /// count — resumed by `handleToolListChangedNotification()`. A test hook:
    /// no product code waits here.
    var toolListChangedGenerationWaiters: [(generation: Int, continuation: CheckedContinuation<Void, Never>)] = []

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

    /// The request id of each bare call that timed out and whose client span
    /// did not end yet — see `MCPServer+CallSpan.swift`. The bare timeout adds
    /// an id, and the end of the client span removes it. A timed-out call
    /// ends with an `isError` result, thus this set is how the error counter
    /// tells a timeout from an `isError` answer of the server.
    var timedOutRequestIDs: Set<ID> = []

    /// The tasks that carry a `notifications/cancelled` to the wire for a
    /// call whose calling `Task` was cancelled — see `CancellationNotices.swift`.
    /// `disconnect()` drains it before it tears the client down, thus every
    /// advisory cancel is on the wire before the transport closes.
    let cancellationNotices = CancellationNotices()

    /// Whether the receive stream of the connected transport ended without a
    /// `disconnect()` — set by `handleTransportDrop(generation:)`, and reset
    /// by the next connect that succeeds. While set, a call that would send a
    /// request throws `MCPServerError.lost` at once, because no answer can
    /// arrive.
    var isTransportDropped = false

    /// Each caller of `waitUntilTransportDropped()` that waits for a
    /// transport drop — resumed by `handleTransportDrop(generation:)`. A test
    /// hook: no product code waits here.
    var transportDropWaiters: [CheckedContinuation<Void, Never>] = []

    /// Every URL-mode elicitation the host's ``elicitationHandler`` accepted
    /// and this actor still holds open, keyed by the wire `elicitationId` —
    /// resumed with `nil` by `complete(elicitationId:)`, and with a cancel by
    /// `endHeldHostElicitations()` when the connection ends. See
    /// `MCPServer+Elicitation.swift`.
    var pendingHostElicitations: [String: CheckedContinuation<ElicitationResponse?, Never>] = [:]

    /// Every URL-mode elicitation that a bound `ToolContext` answers and that
    /// is still open, keyed by the wire `elicitationId`. Each entry holds the
    /// context, the `ToolContext` elicitation id that this actor chose for
    /// the question, and the ``connectGeneration`` of the attempt that got
    /// the request. `complete(elicitationId:generation:)` relays a completion
    /// through it. See `MCPServer+Elicitation.swift`.
    var pendingContextElicitations: [String: (context: ToolContext, id: ULID, generation: Int)] = [:]

    /// Each caller of `waitUntilHostElicitationHeld(elicitationId:)` that
    /// waits until this actor holds the URL-mode flow of that wire id —
    /// resumed by `awaitHostCompletion(of:)`. A test hook: no product code
    /// waits here.
    var hostElicitationHeldWaiters: [(elicitationId: String, continuation: CheckedContinuation<Void, Never>)] = []

    /// Creates a server that makes a new `MCP.Client` named `name` for each
    /// connect attempt.
    ///
    /// In an interactive session, each client declares the elicitation
    /// capability with both `form` and `url`. In a headless session, each
    /// client declares no elicitation capability — see
    /// ``clientCapabilities(for:)``.
    ///
    /// - Parameters:
    ///   - name: The name of this connection — the client name sent at
    ///     `initialize`, and the ``identity`` once the first connect succeeds.
    ///   - version: The client version sent at `initialize`. Defaults to
    ///     ``defaultClientVersion``.
    ///   - clock: The clock `connect(via:backoffPolicy:)` sleeps on between
    ///     retries. Defaults to a real `ContinuousClock`; a test substitutes a
    ///     virtual clock to drive a full backoff schedule with no real delay.
    ///     Never used by the per-attempt timeout, which sleeps on the real
    ///     clock here — a virtual clock that never suspends would make the
    ///     timeout win at once against an attempt in flight.
    ///   - callTimeout: The bound of a call made with no ambient
    ///     `ToolContext` — see ``callTimeout``. Defaults to
    ///     ``defaultCallTimeout``.
    ///   - renderBudget: The render budget every rendered result of this
    ///     server obeys. Defaults to `RenderBudget.default`.
    ///   - elicitationHandler: The host's answerer for a server-initiated
    ///     elicitation that arrives under no `ToolContext` — see
    ///     ``elicitationHandler``. Defaults to `nil`, which answers `cancel`.
    ///   - userPresence: Whether a person is present to answer an
    ///     elicitation — see ``userPresence``. Defaults to `.interactive`.
    ///   - logger: The logger every retry, reconnect and discarded attempt is
    ///     reported to. Defaults to ``defaultLogger``.
    public init(
        name: String,
        version: String = MCPServer.defaultClientVersion,
        clock: any Clock<Duration> = ContinuousClock(),
        callTimeout: Duration = MCPServer.defaultCallTimeout,
        renderBudget: RenderBudget = .default,
        elicitationHandler: ElicitationHandler? = nil,
        userPresence: UserPresence = .interactive,
        logger: Logger = MCPServer.defaultLogger
    ) {
        self.init(
            name: name,
            version: version,
            clock: clock,
            connectAttemptClock: ContinuousClock(),
            callTimeoutClock: ContinuousClock(),
            callTimeout: callTimeout,
            renderBudget: renderBudget,
            elicitationHandler: elicitationHandler,
            userPresence: userPresence,
            logger: logger)
    }

    /// Creates a server whose per-attempt connect timeout sleeps on
    /// `connectAttemptClock`, and whose bare-call timer sleeps on
    /// `callTimeoutClock` — the initializer every other one forwards to.
    ///
    /// Internal: a host has no reason to move these bounds, and the public
    /// initializer gives the real clock to each. A test of a timeout calls
    /// this one through `@testable import`, with a clock it opens on command.
    ///
    /// - Parameters:
    ///   - name: See the public initializer.
    ///   - version: See the public initializer.
    ///   - clock: See the public initializer.
    ///   - connectAttemptClock: The clock the per-attempt timeout of a
    ///     connect sleeps on — see ``connectAttemptClock``.
    ///   - callTimeoutClock: The clock the timer of a bare call sleeps on —
    ///     see ``callTimeoutClock``.
    ///   - callTimeout: See the public initializer.
    ///   - renderBudget: See the public initializer.
    ///   - elicitationHandler: See the public initializer.
    ///   - userPresence: See the public initializer.
    ///   - logger: See the public initializer.
    init(
        name: String,
        version: String,
        clock: any Clock<Duration>,
        connectAttemptClock: any Clock<Duration>,
        callTimeoutClock: any Clock<Duration>,
        callTimeout: Duration,
        renderBudget: RenderBudget,
        elicitationHandler: ElicitationHandler?,
        userPresence: UserPresence,
        logger: Logger
    ) {
        self.name = name
        self.clientVersion = version
        self.clock = clock
        self.connectAttemptClock = connectAttemptClock
        self.callTimeoutClock = callTimeoutClock
        self.callTimeout = callTimeout
        self.renderBudget = renderBudget
        self.elicitationHandler = elicitationHandler
        self.userPresence = userPresence
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

    /// Writes one record to ``logger``, with the name of this server in its
    /// metadata — the one point each log call of `MCPServer` goes through.
    ///
    /// - Parameters:
    ///   - message: The constant message of the record.
    ///   - level: The level of the record.
    ///   - metadata: The other variable values of the record: names, ids,
    ///     counts and sizes only, never a payload.
    func record(
        _ message: MultitoolTelemetry.LogMessage, level: Logger.Level, metadata: Logger.Metadata = [:]
    ) {
        let serverName = MultitoolTelemetry.serverNameMetadata(identityNameForDiagnostics)
        logger.log(message, level: level, metadata: metadata.merging(serverName) { _, name in name })
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
