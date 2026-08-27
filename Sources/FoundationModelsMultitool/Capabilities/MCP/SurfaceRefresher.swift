// `SurfaceRefresher` — the watcher that joins the two halves of
// rebuild-and-swap: it reads the catalog stream of each MCP server, renders a
// new registry at the side when a catalog moved, and stages that registry for
// the next turn boundary.
//
// eventplan.md § "Consolidation of the siblings": "A late server, a reconnect,
// or an MCP `tools/list_changed` starts a full rebuild. MultiTool renders the
// new registry complete at the side. Then MultiTool swaps it in atomically at
// the next turn boundary." `RegistrySource.rebuildRegistry()` is the render,
// and `MultiTool.turnWillBegin()` is the swap. This file is what runs between
// them.
//
// **One stream carries every cause.** `MCPServer.catalogUpdates` emits a
// snapshot for a connect that reached `.ready`, for a connect that failed after
// a prior success, and for a coalesced `tools/list_changed` re-list. A
// reconnect is a connect, so it comes through the same stream. No second path
// is necessary, and this file holds none.
//
// **No task starts in a factory.** `MultiTool.Registry.makeSessionTools(...)`
// and `makeSessionToolsAndStaging(...)` stay synchronous and start nothing, so
// a unit test builds a registry as many times as it likes and leaves no task
// behind. The host makes this refresher after the session tools and calls
// `start()`; `MCPServerPool.shutdownAll()` calls `stop()` through the
// `Stoppable` attachment, before it closes any server.
//
// **The owner and the lifetime are separate.** The watch task holds the rebuild
// half of this type and never the refresher itself. So a refresher a host
// releases without a `stop()` is deallocated while its task runs, and `deinit`
// says so in a debug build. A task that held the refresher would keep it alive
// forever instead, and the mistake would be silent.
//
// **The first snapshot of each server always rebuilds.** An `AsyncStream` holds
// what it emitted before a consumer read it, so the snapshot of the connect
// usually arrives first. One rebuild of a catalog that did not move is the cost
// of never missing a change that landed before the watch started.

import Synchronization
import os

/// Watches the catalog of each MCP server of one session, and stages a rebuilt
/// registry whenever a catalog moves.
///
/// A host makes one of these after it mounts the session tools:
///
/// ```swift
/// let builder = try await MultiTool.Builder().withMCP(servers: [github])
/// let (tools, staging) = try builder.buildRegistry()
///     .makeSessionToolsAndStaging(librarian: nil)
/// let refresher = SurfaceRefresher(
///     source: builder.registrySource, staging: staging, servers: [github])
/// refresher.start()
/// await builder.serverPool.attach(attachment: refresher)
/// ```
///
/// From then on a `tools/list_changed`, a reconnect, or a late server added
/// through ``addServer(_:)`` reaches the surface at the next turn boundary,
/// with no further host action.
///
/// Several snapshots between two turn boundaries give one swap: each one
/// stages, and `RegistryStaging` keeps only the newest.
///
/// - Important: ``stop()`` ends the watch for good. It cancels the task, and a
///   cancelled consumer finishes the `AsyncStream` it was reading, so a
///   refresher that stopped never starts again. A host that stopped a session
///   makes a new refresher for the next one.
public final class SurfaceRefresher: Sendable, Stoppable {
    /// The logger ``init(source:staging:servers:logger:)`` takes when the host
    /// supplies none.
    public static let defaultLogger = Logger(
        subsystem: "FoundationModelsMultitool", category: "SurfaceRefresher")

    /// The first word of the line a failed rebuild writes, which a test reads
    /// the line back by.
    static let rebuildFailureLogPrefix = "surfaceRebuildFailed"

    /// The rebuild half: the recorded registrations, the last built catalog of
    /// each server, and the staging each rebuilt registry goes to.
    ///
    /// Held by the watch task, so the task keeps this and never the refresher
    /// — see the header of this file.
    private let rebuilding: Rebuilding

    /// The lifetime half: the servers to watch, the watch task, and the stream
    /// a late server joins through.
    private let lifetime: Mutex<Lifetime>

    /// What the lifetime lock guards.
    private struct Lifetime: Sendable {
        /// Every server to watch, in the order it was added.
        var servers: [MCPServer]

        /// The one task ``start()`` ran, or `nil` before a start and after a
        /// ``stop()``.
        var task: Task<Void, Never>?

        /// The continuation ``addServer(_:)`` yields a late server to, so the
        /// running task takes up its stream. `nil` while no task runs.
        var joining: AsyncStream<MCPServer>.Continuation?
    }

    /// Creates a refresher over the recorded registrations of a build.
    ///
    /// Starts nothing. The host calls ``start()`` when the session tools are
    /// mounted.
    ///
    /// - Parameters:
    ///   - source: The recorded registrations the rebuild renders again —
    ///     `MultiTool.Builder.registrySource` of the build that made the
    ///     mounted registry.
    ///   - staging: Where each rebuilt registry is staged. The
    ///     `makeSessionToolsAndStaging(librarian:sampleGenerator:)` call that
    ///     mounted the session vends it.
    ///   - servers: The servers to watch, which the host connected before the
    ///     build.
    ///   - logger: Where a failed rebuild is reported. Defaults to
    ///     ``defaultLogger``.
    public init(
        source: MultiTool.RegistrySource,
        staging: any RegistryStaging,
        servers: [MCPServer],
        logger: Logger = SurfaceRefresher.defaultLogger
    ) {
        self.rebuilding = Rebuilding(source: source, staging: staging, logger: logger)
        self.lifetime = Mutex(Lifetime(servers: servers, task: nil, joining: nil))
    }

    /// Refuses a refresher released while its watch task still runs, in a
    /// debug build.
    ///
    /// The task holds ``rebuilding`` and never this refresher, so this point is
    /// reachable with a task still going: it means the host never called
    /// ``stop()``, and the watch would go on re-listing against servers nobody
    /// reads any more.
    deinit {
        assert(
            lifetime.withLock { $0.task == nil },
            "A SurfaceRefresher was released while its watch task ran. The host must call stop(), "
                + "which MCPServerPool.shutdownAll() does for an attached refresher.")
    }

    /// Whether the watch task is held — `false` before a ``start()`` and after
    /// a ``stop()`` returns.
    ///
    /// Internal: the suite of this type reads it to prove that a stop ended the
    /// task. Nothing in this package reads it.
    var isWatching: Bool {
        lifetime.withLock { $0.task != nil }
    }

    /// Starts the one task that reads the catalog stream of each server.
    ///
    /// Each snapshot whose delta against the last built catalog of that server
    /// is not empty rebuilds the registry and stages it. A snapshot of a server
    /// with no last built catalog always rebuilds: with no record, nothing can
    /// say the catalog did not move.
    ///
    /// A rebuild that throws is reported on one line and changes no surface;
    /// the next snapshot of that server tries again.
    ///
    /// Calling this on a refresher that already started does nothing.
    public func start() {
        let rebuilding = self.rebuilding
        let (joining, continuation) = AsyncStream<MCPServer>.makeStream()
        let started = lifetime.withLock { lifetime -> Bool in
            guard lifetime.task == nil else { return false }
            lifetime.joining = continuation
            let servers = lifetime.servers
            lifetime.task = Task {
                await Self.watch(servers, joinedBy: joining, through: rebuilding)
            }
            return true
        }
        if !started {
            continuation.finish()
        }
    }

    /// Cancels the watch task and returns once it has ended.
    ///
    /// `MCPServerPool.shutdownAll()` calls this before it disconnects any
    /// server, so nothing re-lists against a server the pool is closing.
    /// Calling this on a refresher that never started, or that already stopped,
    /// does nothing.
    public func stop() async {
        let stopping = lifetime.withLock {
            lifetime -> (task: Task<Void, Never>, joining: AsyncStream<MCPServer>.Continuation?)? in
            guard let task = lifetime.task else { return nil }
            let joining = lifetime.joining
            lifetime.task = nil
            lifetime.joining = nil
            return (task, joining)
        }
        guard let stopping else { return }
        stopping.joining?.finish()
        stopping.task.cancel()
        await stopping.task.value
    }

    /// Adds a server the host connected after the build, and stages a registry
    /// that holds its verbs.
    ///
    /// The server joins the watch as well, so its own later `tools/list_changed`
    /// reaches the surface the way every other server's does. A refresher that
    /// has not started yet records the server, and ``start()`` watches it.
    ///
    /// - Parameter server: The server the host connected.
    /// - Throws: `MCPServerError.notReady(_:)` when `server` cannot reach
    ///   `.ready`, and what `MultiTool.RegistrySource.rebuildRegistry()` throws
    ///   when the catalogs no longer render.
    public func addServer(_ server: MCPServer) async throws {
        let joining = lifetime.withLock { lifetime -> AsyncStream<MCPServer>.Continuation? in
            lifetime.servers.append(server)
            return lifetime.joining
        }
        joining?.yield(server)
        try await rebuilding.register(server)
    }

    /// Reads the catalog stream of every server, and of every server that
    /// joins later, until the task is cancelled.
    ///
    /// One child task for each server: an `AsyncStream` has one consumer, and
    /// a merged read of several streams is one reader for each of them. The
    /// parent reads `joining`, so a server added later gets a child task of its
    /// own without a second watch task.
    ///
    /// - Parameters:
    ///   - servers: The servers to read from the start.
    ///   - joining: The stream each later server arrives on. ``stop()``
    ///     finishes it, which ends this method once every child has ended.
    ///   - rebuilding: What each snapshot is handed to.
    private static func watch(
        _ servers: [MCPServer],
        joinedBy joining: AsyncStream<MCPServer>,
        through rebuilding: Rebuilding
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask { await rebuilding.follow(server) }
            }
            for await joined in joining {
                group.addTask { await rebuilding.follow(joined) }
            }
        }
    }

    /// The rebuild half of a refresher: what a snapshot is measured against,
    /// what it renders, and where the result is staged.
    ///
    /// A type of its own, and not the refresher itself, so the watch task holds
    /// this and never the refresher — see the header of this file.
    private final class Rebuilding: Sendable {
        /// What the lock guards.
        private struct State: Sendable {
            /// The recorded registrations to render again. ``register(_:)``
            /// appends the capability of a late server to it.
            var source: MultiTool.RegistrySource

            /// The catalog the last successful rebuild of each server read,
            /// keyed by that server's identity. A snapshot is measured against
            /// the entry of its own server.
            var lastCatalogs: [ServerIdentity: MCPToolCatalog]
        }

        /// Where each rebuilt registry is staged.
        private let staging: any RegistryStaging

        /// Where a failed rebuild is reported.
        private let logger: Logger

        /// The guarded state. A `Mutex`, not an actor: every operation on it is
        /// a synchronous decision on a small value, and the awaits of a rebuild
        /// all stand outside the lock.
        private let state: Mutex<State>

        /// Creates the rebuild half.
        ///
        /// - Parameters:
        ///   - source: The recorded registrations to render again.
        ///   - staging: Where each rebuilt registry is staged.
        ///   - logger: Where a failed rebuild is reported.
        init(source: MultiTool.RegistrySource, staging: any RegistryStaging, logger: Logger) {
            self.staging = staging
            self.logger = logger
            self.state = Mutex(State(source: source, lastCatalogs: [:]))
        }

        /// Reads every snapshot of `server` until the stream ends or the task
        /// is cancelled.
        ///
        /// - Parameter server: The server to read.
        func follow(_ server: MCPServer) async {
            for await snapshot in server.catalogUpdates {
                guard !Task.isCancelled else { return }
                await apply(snapshot)
            }
        }

        /// Adds `server` to the recorded registrations and stages a registry
        /// that holds its verbs.
        ///
        /// - Parameter server: The server the host connected late.
        /// - Throws: What `MCPCapability.init(server:)` and
        ///   `MultiTool.RegistrySource.rebuildRegistry()` throw.
        func register(_ server: MCPServer) async throws {
            let capability = try await MCPCapability(server: server)
            let source = state.withLock { state -> MultiTool.RegistrySource in
                state.source.registrations.append(.capability(capability))
                return state.source
            }
            staging.stage(try await source.rebuildRegistry())
        }

        /// Rebuilds and stages when `snapshot` shows the catalog of its server
        /// moved, and does nothing when it does not.
        ///
        /// The snapshot becomes the new last built catalog only after the
        /// rebuild succeeded, so a failure leaves the next snapshot measured
        /// against the same catalog and the rebuild is tried again.
        ///
        /// - Parameter snapshot: The snapshot the server emitted.
        private func apply(_ snapshot: MCPToolCatalog) async {
            guard let source = sourceIfMoved(by: snapshot) else { return }
            do {
                staging.stage(try await source.rebuildRegistry())
                state.withLock { $0.lastCatalogs[snapshot.identity] = snapshot }
            } catch {
                // A stop cancels the rebuild in flight. That is the host ending
                // the session, and not a catalog this refresher cannot render.
                guard !Task.isCancelled else { return }
                logger.warning(
                    "\(SurfaceRefresher.rebuildFailureLogPrefix, privacy: .public) server=\(snapshot.identity.name, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        }

        /// The recorded registrations to render, when `snapshot` shows a
        /// catalog that moved, and `nil` when it shows one that did not.
        ///
        /// - Parameter snapshot: The snapshot to measure.
        /// - Returns: The registrations to render, or `nil` to do nothing.
        private func sourceIfMoved(by snapshot: MCPToolCatalog) -> MultiTool.RegistrySource? {
            state.withLock { state in
                guard let previous = state.lastCatalogs[snapshot.identity] else {
                    return state.source
                }
                return snapshot.diff(from: previous).isEmpty ? nil : state.source
            }
        }
    }
}
