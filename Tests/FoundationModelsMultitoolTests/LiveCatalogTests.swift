import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the dynamic half of the catalog of `MCPServer`: the
/// `catalogUpdates` stream, the coalescing of a `tools/list_changed` burst
/// into one re-list, the snapshot a reconnect emits, the snapshot a failed
/// reconnect emits, `tool(named:)` against the current catalog, and the
/// three stages of the dynamic toolset scenario of `ScriptedServer`.
///
/// A port of the live cases of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/LiveCatalogTests.swift`.
/// Every case that exercises the coalesce window drives an injected clock, so
/// the window sleeps for no real time. A case that sends a burst of more than
/// one notification drives a `GatedClock`, and it opens the window only after
/// the server counted the whole burst (see `emitBurstInOneWindow`).
///
/// **Two cases of the source are not here.**
/// `midCallFaultEmitsFaultedThenReadySnapshots` and
/// `modelCallOnVanishedToolShortCircuitsToNotAvailableResult` each drive the
/// call path — `server.call(toolNamed:)`, `MCPTool`, the follow-up tools —
/// which this package does not port; a later task rewrites the call path
/// onto the run plane of Router.
@Suite("LiveCatalogTests")
struct LiveCatalogTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with, and so the
    /// identity every snapshot carries.
    private static let serverName = "live-catalog-server"

    /// The tool every scripted server of this suite starts with.
    private static let initialToolName = "echo"

    /// The tool a scripted server adds partway through.
    private static let addedToolName = "search"

    /// The tool a scripted server adds after ``addedToolName``.
    private static let secondAddedToolName = "archive"

    /// The size of a "rapid burst" of `tools/list_changed` notifications.
    private static let burstCount = 5

    /// The epoch of the snapshot the first connect emits.
    private static let firstEpoch = 1

    /// The epoch of the snapshot one coalesced burst emits after the first
    /// connect.
    private static let secondEpoch = 2

    /// How many snapshots the stream holds right after the first connect.
    private static let snapshotsAfterConnect = 1

    /// How many snapshots the stream holds after one more emission.
    private static let snapshotsAfterOneMore = 2

    /// How many snapshots the stream holds after two more emissions.
    private static let snapshotsAfterTwoMore = 3

    /// How many snapshots the dynamic scenario produces: the connect, then
    /// one per stage of `advanceDynamicToolsetScenario()`.
    private static let dynamicScenarioSnapshots = 4

    /// How many coalesce windows one burst asks for: one watcher sleeps one
    /// window for the whole burst.
    private static let oneCoalesceWindow = 1

    /// How many leading connect attempts the flaky transport of the failed
    /// reconnect case fails.
    private static let oneFailingAttempt = 1

    // MARK: - Helpers

    /// Collects every `MCPToolCatalog` snapshot read from `catalogUpdates`,
    /// in emission order.
    private actor CatalogSnapshotRecorder {
        /// Every snapshot recorded so far.
        private(set) var snapshots: [MCPToolCatalog] = []

        /// Appends one snapshot.
        ///
        /// - Parameter snapshot: The snapshot to record.
        func append(_ snapshot: MCPToolCatalog) {
            snapshots.append(snapshot)
        }
    }

    /// The recorder of one test and the task that feeds it.
    private struct Recording {
        /// The recorder every snapshot lands in.
        let recorder: CatalogSnapshotRecorder

        /// The task iterating `catalogUpdates`; cancelled when the test ends.
        let task: Task<Void, Never>

        /// Polls until at least `count` snapshots were recorded, or the poll
        /// deadline passes.
        ///
        /// - Parameter count: The minimum number of snapshots to wait for.
        /// - Returns: The snapshots at the moment `count` was reached, or at
        ///   the deadline, whichever came first.
        func snapshots(atLeast count: Int) async -> [MCPToolCatalog] {
            _ = await TestPoll.holds { await recorder.snapshots.count >= count }
            return await recorder.snapshots
        }
    }

    /// Starts a background task that records every snapshot of `server`.
    ///
    /// - Parameter server: The server to subscribe to.
    /// - Returns: The recording; the caller cancels its task when done.
    private func recordCatalogUpdates(from server: MCPServer) async -> Recording {
        let recorder = CatalogSnapshotRecorder()
        let stream = await server.catalogUpdates
        let task = Task {
            for await snapshot in stream {
                await recorder.append(snapshot)
            }
        }
        return Recording(recorder: recorder, task: task)
    }

    /// A `ScriptedServer` named ``serverName`` serving ``initialToolName``.
    ///
    /// - Returns: The scripted server, not yet started.
    private static func scriptedServerWithInitialTool() async -> ScriptedServer {
        let scripted = ScriptedServer(name: serverName)
        await scripted.addEchoTool(named: initialToolName)
        return scripted
    }

    /// The names of the tools of `snapshot`, as a set.
    ///
    /// - Parameter snapshot: The snapshot to read.
    /// - Returns: The tool names.
    private static func toolNames(of snapshot: MCPToolCatalog) -> Set<String> {
        Set(snapshot.tools.map(\.name))
    }

    /// Records a failure unless `epochs` strictly increase.
    ///
    /// - Parameter snapshots: The snapshots whose epochs to check.
    private func expectStrictlyIncreasingEpochs(_ snapshots: [MCPToolCatalog]) {
        let epochs = snapshots.map(\.epoch)
        #expect(epochs == epochs.sorted())
        #expect(Set(epochs).count == epochs.count)
    }

    /// Sends a burst of ``burstCount`` notifications from `scripted`, and
    /// ends the coalesce window of `server` only after `server` counted each
    /// one.
    ///
    /// The window sleeps on `windowClock`, and that clock holds the sleep
    /// until the test opens it. A window on a clock that ends at once can
    /// end before the last notification of the burst arrives, and a slow
    /// machine then splits one burst into two re-lists. No test checks the
    /// speed of the machine (card `^pfvdg5b`), thus the event that opens the
    /// window is the count of the server, and not a time.
    ///
    /// - Parameters:
    ///   - scripted: The server that sends the burst.
    ///   - server: The server whose window coalesces the burst.
    ///   - windowClock: The clock `server` sleeps its window on.
    /// - Throws: What the burst throws, and `TestPoll.ConditionNeverHeld`
    ///   when the server never counts the whole burst.
    private static func emitBurstInOneWindow(
        from scripted: ScriptedServer, to server: MCPServer, windowClock: GatedClock
    ) async throws {
        let generationBefore = await server.toolListChangedGeneration
        try await scripted.emitToolListChangedBurst(count: burstCount)
        try await TestPoll.waitUntil("the server counted the whole burst") {
            await server.toolListChangedGeneration == generationBefore + burstCount
        }
        windowClock.open()
    }

    // MARK: - Coalescing

    @Test func coalescesRapidBurstIntoOneRelist() async throws {
        let scripted = await Self.scriptedServerWithInitialTool()
        let windowClock = GatedClock()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName, clock: windowClock)
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }

        // The connect emits its own snapshot; wait for it, so the assertions
        // below count only what the burst produced.
        let afterConnect = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)
        #expect(afterConnect.count == Self.snapshotsAfterConnect)
        #expect(afterConnect.first?.epoch == Self.firstEpoch)

        await scripted.addTool(ScriptedServer.echoTool(named: Self.addedToolName))
        try await Self.emitBurstInOneWindow(from: scripted, to: server, windowClock: windowClock)

        let afterBurst = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)

        // The burst coalesced into one re-list, not five: one watcher asked
        // for one window, and the server emitted one snapshot after the
        // connect.
        #expect(windowClock.recordedSleeps.count == Self.oneCoalesceWindow)
        #expect(await server.catalogEpoch == Self.secondEpoch)
        #expect(afterBurst.count == Self.snapshotsAfterOneMore)
        #expect(afterBurst.last?.epoch == Self.secondEpoch)
        #expect(
            afterBurst.last.map(Self.toolNames(of:))
                == [Self.initialToolName, Self.addedToolName])
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Epoch monotonicity

    @Test func epochsStrictlyIncreaseAcrossEmissions() async throws {
        let first = await Self.scriptedServerWithInitialTool()
        let windowClock = GatedClock()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: first, over: .inMemory, name: Self.serverName, clock: windowClock)
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }
        _ = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)

        // A coalesced re-list.
        await first.addTool(ScriptedServer.echoTool(named: Self.addedToolName))
        try await Self.emitBurstInOneWindow(from: first, to: server, windowClock: windowClock)
        _ = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)

        // A reconnect to a differently-tooled server, same actor — an
        // implicit re-list: "the returning server may differ".
        let second = await Self.scriptedServerWithInitialTool()
        await second.addTool(ScriptedServer.echoTool(named: Self.addedToolName))
        await second.addTool(ScriptedServer.echoTool(named: Self.secondAddedToolName))
        let transport = try await MCPTestSupport.clientTransport(serving: second, over: .inMemory)
        try await server.connect(via: transport)

        let afterReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterTwoMore)

        #expect(afterReconnect.count == Self.snapshotsAfterTwoMore)
        expectStrictlyIncreasingEpochs(afterReconnect)
        // Every snapshot is complete: a consumer reads the whole tool set
        // from any one of them alone.
        #expect(afterReconnect.map(Self.toolNames(of:)) == [
            [Self.initialToolName],
            [Self.initialToolName, Self.addedToolName],
            [Self.initialToolName, Self.addedToolName, Self.secondAddedToolName],
        ])
        withExtendedLifetime((first, second)) {}
    }

    // MARK: - A reconnect implies a re-list

    @Test func reconnectEmitsSnapshotReflectingReturningServer() async throws {
        let first = await Self.scriptedServerWithInitialTool()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: first, over: .inMemory, name: Self.serverName)
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }
        let beforeReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)
        #expect(beforeReconnect.first?.epoch == Self.firstEpoch)

        await server.disconnect()

        let second = await Self.scriptedServerWithInitialTool()
        await second.addTool(ScriptedServer.echoTool(named: Self.addedToolName))
        let transport = try await MCPTestSupport.clientTransport(serving: second, over: .inMemory)
        try await server.connect(via: transport)

        let afterReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)
        #expect(afterReconnect.count == Self.snapshotsAfterOneMore)
        expectStrictlyIncreasingEpochs(afterReconnect)
        #expect(
            afterReconnect.last.map(Self.toolNames(of:))
                == [Self.initialToolName, Self.addedToolName])
        // The identity stays put across the reconnect even though the tool
        // set changed — the returning server is still "the same server".
        #expect(afterReconnect.first?.identity == afterReconnect.last?.identity)
        withExtendedLifetime((first, second)) {}
    }

    /// The reconnect through `reconnect()` — the retained factory called
    /// again — emits exactly one snapshot, with the tools of the fresh
    /// server the factory built.
    @Test func reconnectThroughRetainedFactoryEmitsOneSnapshot() async throws {
        let respawning = RespawningTransport {
            let (client, transport) = await InMemoryTransport.createConnectedPair()
            let scripted = await Self.scriptedServerWithInitialTool()
            await scripted.addTool(ScriptedServer.echoTool(named: Self.addedToolName))
            try await scripted.start(transport: transport)
            return (client, scripted)
        }
        let server = MCPTestSupport.makeServer(name: Self.serverName)
        try await server.connect(via: respawning, backoffPolicy: .default)
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }
        _ = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)

        await respawning.disconnect()
        try await server.reconnect()

        let afterReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)
        // `reconnect()` emits its snapshot before it returns, thus the epoch
        // the server holds now counts every snapshot of the reconnect: one.
        #expect(await server.catalogEpoch == Self.secondEpoch)
        #expect(afterReconnect.count == Self.snapshotsAfterOneMore)
        #expect(afterReconnect.last?.state == .ready)
        expectStrictlyIncreasingEpochs(afterReconnect)
        #expect(
            afterReconnect.last.map(Self.toolNames(of:))
                == [Self.initialToolName, Self.addedToolName])
    }

    // MARK: - A readiness-state change

    @Test func failedReconnectEmitsFaultedSnapshot() async throws {
        let scripted = await Self.scriptedServerWithInitialTool()
        let transport = try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory)
        let server = MCPTestSupport.makeServer(name: Self.serverName)
        try await server.connect(via: transport)
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }
        let beforeReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)
        #expect(beforeReconnect.count == Self.snapshotsAfterConnect)
        #expect(beforeReconnect.first?.epoch == Self.firstEpoch)
        #expect(beforeReconnect.first?.state == .ready)

        let flaky = FlakyConnectTransport(
            wrapping: transport, failingConnectAttempts: Self.oneFailingAttempt)
        await #expect(throws: (any Error).self) {
            try await server.connect(via: flaky)
        }

        let afterFailedReconnect = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)
        #expect(afterFailedReconnect.count == Self.snapshotsAfterOneMore)
        expectStrictlyIncreasingEpochs(afterFailedReconnect)
        guard case .faulted = afterFailedReconnect.last?.state else {
            Issue.record("expected the second snapshot to carry .faulted after the failed reconnect")
            return
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - tool(named:) resolution

    @Test func toolResolutionReturnsNilAfterScriptedRemoval() async throws {
        let scripted = await Self.scriptedServerWithInitialTool()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName, clock: ManualClock())
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }
        _ = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)

        let resolvedBeforeRemoval = await server.tool(named: Self.initialToolName)
        #expect(resolvedBeforeRemoval?.name == Self.initialToolName)

        await scripted.removeTool(named: Self.initialToolName)
        try await scripted.emitToolListChangedBurst(count: Self.burstCount)
        _ = await recording.snapshots(atLeast: Self.snapshotsAfterOneMore)

        let resolvedAfterRemoval = await server.tool(named: Self.initialToolName)
        #expect(resolvedAfterRemoval == nil)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The dynamic toolset scenario

    /// The three stages of the dynamic toolset scenario — add, re-schema,
    /// remove — each send one `tools/list_changed`, and each produces one
    /// snapshot whose diff against the previous one classifies exactly that
    /// stage.
    ///
    /// The test runs each stage on command, and waits for the snapshot of
    /// one stage before it runs the next. Thus no timer decides which stage
    /// a snapshot sees, and no two stages share one re-list.
    @Test func dynamicToolsetScenarioEmitsOneSnapshotPerStage() async throws {
        let scripted = ScriptedServer(name: Self.serverName)
        await scripted.startDynamicToolsetScenario()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName, clock: ManualClock())
        let recording = await recordCatalogUpdates(from: server)
        defer { recording.task.cancel() }

        _ = await recording.snapshots(atLeast: Self.snapshotsAfterConnect)
        for stage in 1...ScriptedServer.dynamicToolsetStageCount {
            #expect(await scripted.advanceDynamicToolsetScenario())
            _ = await recording.snapshots(atLeast: Self.snapshotsAfterConnect + stage)
        }

        let snapshots = await recording.recorder.snapshots
        try #require(snapshots.count == Self.dynamicScenarioSnapshots)
        expectStrictlyIncreasingEpochs(snapshots)

        let added = snapshots[1].diff(from: snapshots[0])
        #expect(added.added.map(\.name) == [ScriptedServer.dynamicToolsetVanishingToolName])
        #expect(added.removed.isEmpty)
        #expect(added.changed.isEmpty)

        let reschemad = snapshots[2].diff(from: snapshots[1])
        #expect(reschemad.changed.map(\.after.name) == [ScriptedServer.dynamicToolsetReschemadToolName])
        #expect(reschemad.added.isEmpty)
        #expect(reschemad.removed.isEmpty)

        let removed = snapshots[3].diff(from: snapshots[2])
        #expect(removed.removed.map(\.name) == [ScriptedServer.dynamicToolsetVanishingToolName])
        #expect(removed.added.isEmpty)
        #expect(removed.changed.isEmpty)
        withExtendedLifetime(scripted) {}
    }
}
