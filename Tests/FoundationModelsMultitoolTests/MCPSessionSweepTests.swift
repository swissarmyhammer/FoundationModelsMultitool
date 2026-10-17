import Foundation
import FoundationModels
import FoundationModelsExtras
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import FoundationModelsRouter
@testable import MultitoolTestSupport

/// Coverage for the session-end sweep of an MCP call, and for the shutdown of
/// the server subprocesses that follows it — eventplan.md § "Background tools
/// and the completion token": *"MCP requests get the advisory cancel and post
/// `.cancelled` before the transport closes."* And § "Consolidation of the
/// siblings": *"To kill a server subprocess is a host-level act on each
/// in-flight call that it carries. It is not a run cancellation."*
///
/// `ShellSessionSweepTests` is the precedent. The shell sweep kills a process
/// group; the MCP sweep reaches the wire, thus what this suite reads is the
/// ORDER on the wire, through a ``WireRecordingTransport`` on the client end
/// of the in-memory pair: each send by its method, the close, and a marker the
/// test appends for an event of the run plane.
///
/// **Two shapes of an in-flight call.** eventplan.md speaks of "MCP requests"
/// and makes no distinction, and there are two:
///
/// 1. **Parked** — the call runs inside a background `runCode` run. The
///    session sweep, `RunPlane.sweep()`, cancels the run; the Task
///    cancellation reaches `MCPServer.call`, which sends
///    `notifications/cancelled` and throws; the sweep synthesizes the terminal
///    `.cancelled` of the run.
/// 2. **Native** — the `MCPTool` is mounted directly on a `RoutedSession`, as
///    a plain run-to-completion call, and it is never parked. No run-plane
///    entry exists, thus the sweep has nothing to cancel. What ends the call
///    at session end is the cancellation of the task of the open answer
///    (`RoutedSession.cancelAll()` stops it). That cancellation stops the
///    model call that the tool runs inside; the same cancellation reaches `MCPServer.call` the
///    same way, and the advisory cancel still goes out before the transport
///    closes.
///
/// **The order the wire proves.** In each shape the advisory cancel is on the
/// wire BEFORE the transport closes, and in the parked shape the terminal
/// `.cancelled` of the run is recorded before the transport closes as well.
/// The sweep does not wait for the body of a run it cancels: Router's
/// cooperative canceler returns at once and the sweep synthesizes the
/// terminal, while the notification goes out from the task the cancellation
/// started. Thus the order between the notification and the terminal is not
/// fixed, and no test here asserts one. `MCPServer.disconnect()` is what fixes
/// the order against the close: it waits for every notification a
/// cancellation started before it tears the client down.
///
/// **Step 2 — the server subprocesses.** `MCPServerPool.shutdownAll()`
/// disconnects each server and shuts each `StdioServerProcess` down, and it
/// stops an attached `Stoppable` first. A host calls it after the session
/// sweep. Servers are infrastructure with session lifetime, and they get no
/// `completionToken`.
///
/// The subprocess case spawns the `mcp-test-server` executable through the
/// public initializer of `StdioServerProcess`, thus through
/// `ProcessRegistry.global`, and it reads that registry for its own pid alone.
@Suite("MCPSessionSweepTests", .ownsTemporaryDirectories)
struct MCPSessionSweepTests {

    /// The name of the server of the two in-memory cases — the noun the
    /// verbs of the server render under.
    private static let serverName = "sweep"

    /// The name of the server of the subprocess case.
    private static let subprocessServerName = "sweep-subprocess"

    /// The name of the verb whose call holds on the server until the test
    /// releases it, thus the call is still in flight when the sweep reaches
    /// it, whatever the speed of the machine.
    private static let heldToolName = "held"

    /// How many recorded notifications the cancel cases wait for.
    private static let oneNotification = 1

    /// How many terminal events one swept run gets. `RunPlane.sweep()`
    /// states the invariant: exactly one for each run, never two.
    private static let terminalEventsPerRun = 1

    /// How many times one `shutdownAll()` stops the attachment.
    private static let oneStop = 1

    /// The `runCode` snippet of the parked shape: it awaits the held verb of
    /// the server.
    private static let parkedSnippet = "return await tools.\(serverName).\(heldToolName)({});"

    /// The marker the parked case appends once the sweep answered the
    /// terminal of the run.
    private static let terminalMarker = "terminal .cancelled"

    /// The marker the attachment case appends when `stop()` runs.
    private static let stopMarker = "attachment stopped"

    /// The wire entry of the advisory cancel.
    private static let cancelEntry = WireRecordingTransport.Entry.sent(
        method: CancelledNotification.name)

    /// The wire entry of the request that starts the held call.
    private static let callEntry = WireRecordingTransport.Entry.sent(method: CallTool.name)

    // MARK: - The ground of one test

    /// One server that serves the held tool, connected over a recording
    /// transport, and the pool that holds it.
    private struct SweepGround {
        /// The scripted server, which the test keeps alive.
        let scripted: ScriptedServer

        /// The tool whose call holds until the test releases it.
        let held: HeldScriptedTool

        /// The connected server.
        let server: MCPServer

        /// The recording transport the server connected over.
        let wire: WireRecordingTransport

        /// The pool that holds the server.
        let pool: MCPServerPool
    }

    /// A `Stoppable` that records what happened when it was stopped.
    private actor RecordingAttachment: Stoppable {
        /// How many times `stop()` ran.
        private(set) var stopCount = 0

        /// What `stop()` does beside the count.
        private let onStop: @Sendable () async -> Void

        /// Creates an attachment that runs `onStop` on each stop.
        ///
        /// - Parameter onStop: What to do on each stop.
        init(onStop: @escaping @Sendable () async -> Void) {
            self.onStop = onStop
        }

        func stop() async {
            stopCount += 1
            await onStop()
        }
    }

    /// Makes a scripted server that serves the held tool, connected to a
    /// fresh `MCPServer` named ``serverName`` over a recording transport,
    /// and a pool that records that server through `withMCP(servers:)`. Then
    /// it gives the ground to `body`.
    ///
    /// The server disconnects after `body`, also when the build or `body`
    /// throws. A test that shuts the pool down already disconnected the
    /// server, and the second disconnect does nothing.
    ///
    /// - Parameter body: The work of the test on the ground, and on the
    ///   registry the builder rendered.
    /// - Returns: What `body` returned.
    /// - Throws: What the connect, the build or `body` throws.
    private static func withGround<Result>(
        _ body: (SweepGround, MultiTool.Registry) async throws -> Result
    ) async throws -> Result {
        let scripted = ScriptedServer()
        let held = HeldScriptedTool(named: heldToolName)
        await scripted.addTool(held.scriptedTool)
        let (server, wire) = try await MCPTestSupport.connectedRecordingMCPServer(
            to: scripted, name: serverName)
        return try await MCPTestSupport.withConnection(of: server) {
            let builder = try await MultiTool.Builder().withMCP(servers: [server])
            let registry = try builder.buildRegistry()
            let ground = SweepGround(
                scripted: scripted, held: held, server: server, wire: wire, pool: builder.serverPool)
            return try await body(ground, registry)
        }
    }

    /// Waits until the held call of `ground` is on the wire, or until `ended`
    /// returned.
    ///
    /// The wait is an event, not a poll: it waits until the held tool on the
    /// server gets the call — see ``EventRace/firstOf(_:or:)``. It also ends
    /// when `ended` returned, thus a call that ended before it reached the
    /// server does not make the test hang: the test then fails at once.
    ///
    /// - Parameters:
    ///   - ground: The ground whose wire to read.
    ///   - ended: The wait for the event that shows that the call cannot
    ///     reach the server any more, for example the end of the run that
    ///     makes the call. A cancel must end it.
    /// - Throws: When the call did not reach the server, or when the task is
    ///   cancelled first.
    private static func waitForTheCall(
        on ground: SweepGround, orUntil ended: @escaping @Sendable () async -> Void
    ) async throws {
        let held = ground.held
        try await EventRace.firstOf({ try? await held.waitForArrival() }, or: ended)
        try await expectTheCallOnTheWire(of: ground)
    }

    /// Starts `work`, and waits until the held call of `ground` is on the
    /// wire, or until `work` ended — see ``waitForTheCall(on:orUntil:)``.
    ///
    /// - Parameters:
    ///   - ground: The ground whose wire to read.
    ///   - work: The work that makes the held call.
    /// - Returns: The task of `work`.
    /// - Throws: When the call did not reach the server, or when the task is
    ///   cancelled first.
    private static func startTheCall<Success: Sendable>(
        on ground: SweepGround, _ work: @escaping @Sendable () async throws -> Success
    ) async throws -> Task<Success, any Error> {
        let call = EventRace.watch(work)
        try await waitForTheCall(on: ground, orUntil: { await call.waitForEnd() })
        return call.task
    }

    /// Fails the test at once unless the held call of `ground` reached the
    /// server, and records a failure unless the call is on the wire.
    ///
    /// `WireRecordingTransport.send(_:)` records the request before it sends
    /// it, thus a call that reached the server is in the ledger.
    ///
    /// - Parameter ground: The ground whose wire to read.
    /// - Throws: When the call did not reach the server.
    private static func expectTheCallOnTheWire(of ground: SweepGround) async throws {
        try #require(ground.held.hasArrived, "the call ended before it reached the server")
        let ledger = await ground.wire.ledger
        #expect(ledger.contains(callEntry), "the call is not on the wire: \(ledger)")
    }

    /// Asserts that `first` stands before `second` in the ledger of `wire`.
    ///
    /// - Parameters:
    ///   - first: The entry that must come first.
    ///   - second: The entry that must come second.
    ///   - wire: The transport whose ledger to read.
    private static func expectOrder(
        of first: WireRecordingTransport.Entry, before second: WireRecordingTransport.Entry,
        on wire: WireRecordingTransport
    ) async throws {
        let ledger = await wire.ledger
        let firstPosition = try #require(await wire.position(of: first), "\(first) never reached the wire: \(ledger)")
        let secondPosition = try #require(
            await wire.position(of: second), "\(second) never reached the wire: \(ledger)")
        #expect(firstPosition < secondPosition, "the order was: \(ledger)")
    }

    /// Asserts that the scripted server received the advisory cancel.
    ///
    /// - Parameter scripted: The server to read.
    private static func expectServerReceivedTheCancel(from scripted: ScriptedServer) async {
        let recorded = await scripted.waitForRecordedNotifications(count: oneNotification)
        #expect(recorded.first?.method == CancelledNotification.name, "recorded: \(recorded)")
    }

    // MARK: - The parked shape

    /// eventplan.md: *"MCP requests get the advisory cancel and post
    /// `.cancelled` before the transport closes."* The `runCode` run that
    /// awaits the held verb is parked on the run plane; the sweep cancels it,
    /// the cancellation reaches `MCPServer.call`, and the pool then closes
    /// the transport.
    @Test("parked shape: the sweep sends the advisory cancel and records .cancelled before the transport closes")
    func parkedCallGetsTheAdvisoryCancelAndCancelledBeforeTheTransportCloses() async throws {
        try await Self.withGround { ground, registry in
            // The test closes the session itself, at the point its assertions
            // need. The scope also closes the session when the test throws
            // before that point. A second close does nothing. The outer
            // `ensuring` releases the held call on each path.
            try await ensuring({ await ground.held.release() }) {
                try await withStubRun { run in
                    let context = run.context
                    // No inline wait, so the call answers with the pending envelope at
                    // once and the run parks. The stock `inlineSettleGrace` would hold
                    // the call for its whole length before the sweep can run.
                    let mounted = try #require(
                        SessionMount.synchronous(
                            MultiTool(registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 0)),
                            on: context)
                            as? any FoundationModels.Tool<RunCodeArguments, String>)
                    let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.parkedSnippet))
                    #expect(PendingRunEnvelope.isRendered(text: rendered), "answer was: \(rendered)")
                    let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
                    // A run whose call fails before it reaches the server ends
                    // with a terminal event, and that event ends the wait.
                    let runToken = envelope.completionToken
                    try await Self.waitForTheCall(on: ground) {
                        _ = await recordedOperationEvents(
                            of: run, ofKind: .completed, correlatedTo: [runToken],
                            awaiting: Self.terminalEventsPerRun)
                    }

                    // `RoutedSession.close()` runs the sweep — it cancels every background
                    // run, rejects every pending elicitation, and journals the terminal
                    // events before it returns. A consumer cannot call the sweep of the run
                    // plane of the session, so this is the public route to the same behaviour.
                    await run.session.close()
                    let terminals = await recordedOperationEvents(
                        of: run, ofKind: .completed,
                        correlatedTo: [envelope.completionToken],
                        awaiting: Self.terminalEventsPerRun)
                    await ground.wire.mark(as: Self.terminalMarker)
                    await ground.pool.shutdownAll()

                    // Diagnostic: this passes here and fails on CI, and the failure is a
                    // count that is too HIGH rather than too low, so the message carries
                    // what actually landed.
                    #expect(
                        terminals.count == Self.terminalEventsPerRun,
                        """
                        terminals=\(terminals.count)             kinds=\(terminals.map(\.kind))             outcomes=\(terminals.map { String(describing: $0.outcome) })             correlations=\(terminals.map(\.correlationID))             envelope=\(envelope.completionToken)             outer=\(run.context.completionToken)
                        """
                    )
                    let terminal = try #require(terminals.first)
                    #expect(terminal.correlationID == envelope.completionToken)
                    #expect(terminal.kind == .completed)
                    #expect(terminal.outcome == .cancelled)
                    await Self.expectServerReceivedTheCancel(from: ground.scripted)
                    try await Self.expectOrder(of: Self.cancelEntry, before: .disconnected, on: ground.wire)
                    try await Self.expectOrder(
                        of: .marker(Self.terminalMarker), before: .disconnected, on: ground.wire)
                    #expect(await context.backgroundRuns().isEmpty)
                }
            }
            withExtendedLifetime(ground.scripted) {}
        }
    }

    // MARK: - The native shape

    /// The `MCPTool` mounted directly on a session runs to completion, and it
    /// is never parked: no run-plane entry exists, thus the sweep has nothing
    /// to cancel. The cancellation of the task of the open answer is what reaches
    /// `MCPServer.call`, and the advisory cancel still goes out before the
    /// pool closes the transport.
    @Test("native shape: the cancelled answer sends the advisory cancel before the transport closes")
    func nativeCallGetsTheAdvisoryCancelBeforeTheTransportCloses() async throws {
        try await Self.withGround { ground, _ in
            // The `ensuring` releases the held call on each path.
            try await ensuring({ await ground.held.release() }) {
                try await withStubRun { run in
                    let context = run.context
                    let entry = try #require(await ground.server.tool(named: Self.heldToolName))
                    let mounted = try #require(
                        SessionMount.synchronous(
                            MCPTool(entry: entry, server: ground.server), on: context)
                            as? any FoundationModels.Tool<GeneratedContent, String>)
                    let answer = try await Self.startTheCall(on: ground) {
                        try await mounted.call(arguments: GeneratedContent(properties: [:]))
                    }
                    #expect(await context.backgroundRuns().isEmpty, "a native call is never parked")

                    answer.cancel()
                    await #expect(throws: CancellationError.self) {
                        _ = try await answer.value
                    }
                    await ground.pool.shutdownAll()

                    await Self.expectServerReceivedTheCancel(from: ground.scripted)
                    try await Self.expectOrder(of: Self.cancelEntry, before: .disconnected, on: ground.wire)
                }
            }
            withExtendedLifetime(ground.scripted) {}
        }
    }

    // MARK: - The pool

    /// `shutdownAll()` stops the attachment first, then disconnects each
    /// server. The attachment is the hook the surface refresher of a later
    /// task attaches to; here a recording double stands in its place.
    @Test("shutdownAll stops the attachment before it disconnects the servers")
    func shutdownAllStopsTheAttachmentBeforeTheServers() async throws {
        try await Self.withGround { ground, _ in
            let attachment = RecordingAttachment { await ground.wire.mark(as: Self.stopMarker) }
            await ground.pool.attach(attachment: attachment)

            await ground.pool.shutdownAll()

            #expect(await attachment.stopCount == Self.oneStop)
            #expect(await ground.server.state == .disconnected)
            try await Self.expectOrder(
                of: .marker(Self.stopMarker), before: .disconnected, on: ground.wire)
            withExtendedLifetime(ground.scripted) {}
        }
    }

    /// A session with no MCP servers is unchanged: the pool of a builder that
    /// never called `withMCP(servers:)` is empty, and its `shutdownAll()` has
    /// nothing to do.
    @Test("a session with no MCP servers holds an empty pool, and shutdownAll does nothing")
    func aSessionWithNoServersIsUnchanged() async {
        let builder = MultiTool.Builder()

        await builder.serverPool.shutdownAll()

        #expect(await builder.serverPool.isEmpty)
    }

    // MARK: - The server subprocesses

    /// `shutdownAll()` ends each server subprocess, and `ProcessRegistry.global`
    /// no longer holds it. The process is spawned through the public
    /// initializer of `StdioServerProcess`, which registers there.
    @Test("shutdownAll ends the server subprocess, and the global registry no longer holds it")
    func shutdownAllEndsTheServerSubprocess() async throws {
        let stdio = try StdioServerProcess(
            command: TestServerLocator.executableURL().path,
            args: [ServerMode.flagName, ServerMode.echo.rawValue],
            name: Self.subprocessServerName)
        let server = MCPTestSupport.makeServer(name: Self.subprocessServerName)
        try await server.connect(via: stdio.respawn)
        // The disconnect of the server also ends the subprocess. Thus the
        // scope ends the subprocess when the test throws before the
        // `shutdownAll()` under test.
        try await MCPTestSupport.withConnection(of: server) {
            let pid = try #require(stdio.currentPid)
            #expect(ProcessLiveness.isAlive(pid))
            #expect(ProcessRegistry.global.registeredPids.contains(pid))
            let pool = MCPServerPool()
            await pool.add(server: server)
            await pool.add(process: stdio)

            await pool.shutdownAll()

            #expect(await server.state == .disconnected)
            #expect(ProcessLiveness.isGone(pid))
            #expect(!ProcessRegistry.global.registeredPids.contains(pid))
            #expect(await pool.isEmpty)
        }
    }
}
