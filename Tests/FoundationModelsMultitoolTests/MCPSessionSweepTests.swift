import Foundation
import FoundationModels
import FoundationModelsExtras
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import FoundationModelsRouter

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
///    session sweep, `SessionMailbox.sweep()`, cancels the run; the Task
///    cancellation reaches `MCPServer.call`, which sends
///    `notifications/cancelled` and throws; the sweep synthesizes the terminal
///    `.cancelled` of the run.
/// 2. **Native** — the `MCPTool` is mounted directly on a `RoutedSession`, as
///    a plain run-to-completion call, and it is never parked. No run-plane
///    entry exists, thus the sweep has nothing to cancel. What ends the call
///    at session end is the cancellation of the in-flight turn task
///    (`RoutedSession.cancelCurrentTurn()`), which cancels the model call the
///    tool runs inside; the same cancellation reaches `MCPServer.call` the
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
@Suite("MCPSessionSweepTests")
struct MCPSessionSweepTests {

    /// The name of the server of the two in-memory cases — the noun the
    /// verbs of the server render under.
    private static let serverName = "sweep"

    /// The name of the server of the subprocess case.
    private static let subprocessServerName = "sweep-subprocess"

    /// How many progress notifications the slow tool sends — far more than a
    /// test lets run, thus the call is still in flight when the sweep reaches
    /// it.
    private static let slowSteps = 1_000

    /// How long the slow tool waits between notifications.
    private static let slowStepDelay = Duration.milliseconds(20)

    /// How long a test waits for the scripted server to record a
    /// `notifications/cancelled`.
    private static let notificationTimeout = Duration.seconds(5)

    /// How many recorded notifications the cancel cases wait for.
    private static let oneNotification = 1

    /// How many terminal events one swept run gets. `SessionMailbox.sweep()`
    /// states the invariant: exactly one for each run, never two.
    private static let terminalEventsPerRun = 1

    /// How many times one `shutdownAll()` stops the attachment.
    private static let oneStop = 1

    /// The `runCode` snippet of the parked shape: it awaits the slow verb of
    /// the server.
    private static let parkedSnippet =
        "return await tools.\(serverName).\(ServerMode.slowBuildToolName)({});"

    /// The marker the parked case appends once the sweep answered the
    /// terminal of the run.
    private static let terminalMarker = "terminal .cancelled"

    /// The marker the attachment case appends when `stop()` runs.
    private static let stopMarker = "attachment stopped"

    /// The wire entry of the advisory cancel.
    private static let cancelEntry = WireRecordingTransport.Entry.sent(
        method: CancelledNotification.name)

    /// The wire entry of the request that starts the slow call.
    private static let callEntry = WireRecordingTransport.Entry.sent(method: CallTool.name)

    // MARK: - The ground of one test

    /// One server that serves the slow tool, connected over a recording
    /// transport, and the pool that holds it.
    private struct SweepGround {
        /// The scripted server, which the test keeps alive.
        let scripted: ScriptedServer

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

    /// A scripted server that serves the slow tool, connected to a fresh
    /// `MCPServer` named ``serverName`` over a recording transport, and a
    /// pool that records that server through `withMCP(servers:)`.
    ///
    /// - Returns: The ground, and the registry the builder rendered.
    /// - Throws: What the connect or the build throws.
    private static func makeGround() async throws -> (ground: SweepGround, registry: MultiTool.Registry) {
        let scripted = ScriptedServer()
        await scripted.addSlowBuildTool(
            named: ServerMode.slowBuildToolName, totalSteps: slowSteps, stepDelay: slowStepDelay)
        let (server, wire) = try await MCPTestSupport.connectedRecordingMCPServer(
            to: scripted, name: serverName)
        let builder = try await MultiTool.Builder().withMCP(servers: [server])
        let registry = try builder.buildRegistry()
        let ground = SweepGround(scripted: scripted, server: server, wire: wire, pool: builder.serverPool)
        return (ground, registry)
    }

    /// Waits until the slow call of `ground` is on the wire.
    ///
    /// - Parameter ground: The ground whose wire to read.
    /// - Throws: When no call reaches the wire before the deadline.
    private static func waitForTheCall(on ground: SweepGround) async throws {
        try await TestPoll.waitUntil("the call reached the wire") {
            await ground.wire.holds(callEntry)
        }
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
        let recorded = await scripted.waitForRecordedNotifications(
            count: oneNotification, timeout: notificationTimeout)
        #expect(recorded.first?.method == CancelledNotification.name, "recorded: \(recorded)")
    }

    // MARK: - The parked shape

    /// eventplan.md: *"MCP requests get the advisory cancel and post
    /// `.cancelled` before the transport closes."* The `runCode` run that
    /// awaits the slow verb is parked on the run plane; the sweep cancels it,
    /// the cancellation reaches `MCPServer.call`, and the pool then closes
    /// the transport.
    @Test("parked shape: the sweep sends the advisory cancel and records .cancelled before the transport closes")
    func parkedCallGetsTheAdvisoryCancelAndCancelledBeforeTheTransportCloses() async throws {
        let (ground, registry) = try await Self.makeGround()
        let run = try await makeStubRun()
        let context = run.context
        let mounted = try #require(
            SessionMount.synchronous(
                MultiTool(registry: registry), on: context)
                as? any FoundationModels.Tool<RunCodeArguments, String>)
        let rendered = try await mounted.call(arguments: RunCodeArguments(code: Self.parkedSnippet))
        #expect(PendingRunEnvelope.isRendered(text: rendered), "answer was: \(rendered)")
        let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        try await Self.waitForTheCall(on: ground)

        // `RoutedSession.close()` runs the sweep — it cancels every background
        // run, rejects every pending elicitation, and journals the terminal
        // events before it returns. A consumer cannot call the mailbox's own
        // sweep, so this is the public route to the same behaviour.
        await run.session.close()
        let terminals = await recordedOperationEvents(
            of: run, ofKind: .completed, awaiting: Self.terminalEventsPerRun)
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
        withExtendedLifetime(ground.scripted) {}
    }

    // MARK: - The native shape

    /// The `MCPTool` mounted directly on a session runs to completion, and it
    /// is never parked: no run-plane entry exists, thus the sweep has nothing
    /// to cancel. The cancellation of the in-flight turn task is what reaches
    /// `MCPServer.call`, and the advisory cancel still goes out before the
    /// pool closes the transport.
    @Test("native shape: the cancelled turn sends the advisory cancel before the transport closes")
    func nativeCallGetsTheAdvisoryCancelBeforeTheTransportCloses() async throws {
        let (ground, _) = try await Self.makeGround()
        let run = try await makeStubRun()
        let context = run.context
        let entry = try #require(await ground.server.tool(named: ServerMode.slowBuildToolName))
        let mounted = try #require(
            SessionMount.synchronous(
                MCPTool(entry: entry, server: ground.server), on: context)
                as? any FoundationModels.Tool<GeneratedContent, String>)
        let turn = Task { try await mounted.call(arguments: GeneratedContent(properties: [:])) }
        try await Self.waitForTheCall(on: ground)
        #expect(await context.backgroundRuns().isEmpty, "a native call is never parked")

        turn.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await turn.value
        }
        await ground.pool.shutdownAll()

        await Self.expectServerReceivedTheCancel(from: ground.scripted)
        try await Self.expectOrder(of: Self.cancelEntry, before: .disconnected, on: ground.wire)
        withExtendedLifetime(ground.scripted) {}
    }

    // MARK: - The pool

    /// `shutdownAll()` stops the attachment first, then disconnects each
    /// server. The attachment is the hook the surface refresher of a later
    /// task attaches to; here a recording double stands in its place.
    @Test("shutdownAll stops the attachment before it disconnects the servers")
    func shutdownAllStopsTheAttachmentBeforeTheServers() async throws {
        let (ground, _) = try await Self.makeGround()
        let attachment = RecordingAttachment { await ground.wire.mark(as: Self.stopMarker) }
        await ground.pool.attach(attachment: attachment)

        await ground.pool.shutdownAll()

        #expect(await attachment.stopCount == Self.oneStop)
        #expect(await ground.server.state == .disconnected)
        try await Self.expectOrder(
            of: .marker(Self.stopMarker), before: .disconnected, on: ground.wire)
        withExtendedLifetime(ground.scripted) {}
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
        let server = MCPServer(name: Self.subprocessServerName)
        try await server.connect(via: stdio.respawn)
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
