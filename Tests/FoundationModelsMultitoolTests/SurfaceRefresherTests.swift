import Foundation
import FoundationModels
import MCPTestServer
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `SurfaceRefresher` — the watcher that joins the two halves of
/// rebuild-and-swap. eventplan.md § "Consolidation of the siblings": "A late
/// server, a reconnect, or an MCP `tools/list_changed` starts a full rebuild.
/// MultiTool renders the new registry complete at the side. Then MultiTool
/// swaps it in atomically at the next turn boundary."
///
/// `RegistryRebuildTests` covers the rebuild and `RegistrySwapTests` covers the
/// swap. This suite covers the watcher between them, and it drives the turn
/// tick by hand with `MultiTool.turnWillBegin()`, the way a `RoutedSession`
/// drives it.
///
/// Seven facts carry this suite:
///
/// 1. A tool the server adds reaches the surface at the next tick, with no
///    host action, and a snippet calls it.
/// 2. A tool the server removes leaves the surface at the next tick, and a
///    snippet that calls it gets the unknown-tool repair hint.
/// 3. Three changes before one tick give one swap: nothing moves until the
///    tick, and the tick brings the whole burst in.
/// 4. A rebuild that throws keeps the old surface and logs one line, and the
///    next snapshot tries again.
/// 5. `stop()` ends the watch task, and nothing stages after it.
/// 6. A registry mounted with no refresher leaves no task behind: the surface
///    never moves.
/// 7. `addServer(_:)` puts a late server's verbs on the surface, and the late
///    server is watched for its own changes after that.
///
/// **Every server sleeps on a `ManualClock`**, so the coalesce window of a
/// `tools/list_changed` re-list takes no real time — the convention of
/// `LiveCatalogTests` and `RegistryRebuildTests`.
///
/// **The connect emits a snapshot of its own**, and an `AsyncStream` holds what
/// it emitted before a consumer read it. So the refresher rebuilds one time as
/// it starts, before any change. Each case waits for that first stage, and
/// counts the stages of its own changes above it.
@Suite("SurfaceRefresherTests")
struct SurfaceRefresherTests {

    // MARK: - Shared test constants

    /// The name of the server of the dynamic-scenario cases, and so the noun
    /// its verbs render under.
    private static let dynamicServerName = "dynamic"

    /// The name of the server of the burst case.
    private static let burstServerName = "burst"

    /// The name of the server of the rebuild-failure case.
    private static let failureServerName = "failing"

    /// The name of the server of the `stop()` case.
    private static let stoppedServerName = "stopped"

    /// The name of the server of the no-refresher case.
    private static let unwatchedServerName = "unwatched"

    /// The name of the server the late-server cases start with.
    private static let firstServerName = "first"

    /// The name of the server the late-server cases add through
    /// ``SurfaceRefresher/addServer(_:)``.
    private static let lateServerName = "late"

    /// The rendered path of the tool the dynamic scenario starts with.
    private static let counterPath =
        "\(dynamicServerName).\(ScriptedServer.dynamicToolsetReschemadToolName)"

    /// The rendered path of the tool the dynamic scenario adds and later
    /// removes.
    private static let greeterPath =
        "\(dynamicServerName).\(ScriptedServer.dynamicToolsetVanishingToolName)"

    /// The text the snippet of ``greeterSnippet`` asks the greeter to echo.
    private static let greeting = "hello"

    /// The snippet that calls the greeter verb of the dynamic server.
    private static let greeterSnippet =
        "return await tools.\(greeterPath)({ \(ScriptedServer.echoTextArgument): \"\(greeting)\" });"

    /// The name of the first tool the burst case adds.
    private static let alphaToolName = "alpha"

    /// The name of the second tool the burst case adds.
    private static let betaToolName = "beta"

    /// The name of the third tool the burst case adds.
    private static let gammaToolName = "gamma"

    /// A tool name that is not a legal TypeScript identifier, which a server
    /// may publish and the renderer must refuse.
    private static let illegalVerb = "bad verb!"

    /// The name of the tool the rebuild-failure case publishes to prove the
    /// next snapshot tries again.
    private static let recoveredToolName = "recovered"

    /// How many `tools/list_changed` notifications a case sends after one
    /// mutation. One is enough; the re-list coalesces a burst anyway.
    private static let oneNotification = 1

    /// How many registries the refresher stages for the snapshot of the
    /// connect alone, before any change.
    private static let stagesAfterConnect = 1

    /// How many registries the refresher has staged after one change.
    private static let stagesAfterOneChange = 2

    /// How many registries the refresher has staged after two changes.
    private static let stagesAfterTwoChanges = 3

    /// How many registries the refresher has staged after three changes.
    private static let stagesAfterThreeChanges = 4

    /// How many lines one failed rebuild writes to the log.
    private static let oneLogLine = 1

    /// How long a case waits, after the change it expects nothing from, to
    /// prove that no stage follows — a fixed, bounded interval, because the
    /// whole point is that nothing happens.
    private static let noFurtherStageSettleDelay = Duration.milliseconds(200)

    /// How long a case waits for the log store to catch up with the line a
    /// failed rebuild wrote. Generous: a miss would make a genuine line look
    /// like a missing one, and the wait ends the instant the line arrives.
    private static let logReadbackDeadline = Duration.seconds(20)

    // MARK: - The ground of one test

    /// A `RegistryStaging` that counts each staged registry and passes it on
    /// to the staging the mounted session vended.
    ///
    /// The count is what a case reads to learn that a rebuild finished: a
    /// stage is the last step of the watcher's work for one snapshot.
    private final class RecordingStaging: RegistryStaging {
        /// The staging of the mounted session, which every staged registry is
        /// passed on to.
        private let mounted: any RegistryStaging

        /// How many registries were staged so far.
        private let stages = Mutex(0)

        /// Creates a staging that records, and then passes on to `mounted`.
        ///
        /// - Parameter mounted: The staging the mounted session vended.
        init(passingTo mounted: any RegistryStaging) {
            self.mounted = mounted
        }

        /// How many registries this staging recorded so far.
        var count: Int {
            stages.withLock { $0 }
        }

        /// Records `registry`, and then stages it on the mounted staging.
        ///
        /// - Parameter registry: The registry to stage.
        func stage(_ registry: MultiTool.Registry) {
            stages.withLock { $0 += 1 }
            mounted.stage(registry)
        }
    }

    /// The pieces one case drives: the connected server, the mounted
    /// `runCode`, the staging that counts, and the refresher under test.
    private struct Ground {
        /// The connected server the refresher watches.
        let server: MCPServer

        /// The `runCode` the mounted session holds, whose `turnWillBegin()`
        /// is the turn tick of a case.
        let runCode: MultiTool

        /// The staging the refresher stages on, which counts each stage.
        let staging: RecordingStaging

        /// The refresher under test.
        let refresher: SurfaceRefresher
    }

    /// Connects an `MCPServer` named `name` against `scripted`, builds a
    /// registry over it, mounts the session tools, and makes a refresher over
    /// the mounted staging.
    ///
    /// - Parameters:
    ///   - name: The name of the server, and so the noun its verbs render
    ///     under.
    ///   - scripted: The scripted server to serve on the far end.
    /// - Returns: The ground of one case.
    /// - Throws: What the connect, the build, or the mount throws.
    private static func makeGround(
        named name: String, serving scripted: ScriptedServer
    ) async throws -> Ground {
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: name, clock: ManualClock())
        let builder = try await MultiTool.Builder().withMCP(servers: [server])
        let (tools, staging) = try builder.buildRegistry()
            .makeSessionToolsAndStaging(librarian: nil)
        let recording = RecordingStaging(passingTo: staging)
        return Ground(
            server: server,
            runCode: try #require(tools.compactMap { $0 as? MultiTool }.first),
            staging: recording,
            refresher: SurfaceRefresher(
                source: builder.registrySource, staging: recording, servers: [server])
        )
    }

    /// Runs `body` over a started refresher, and stops that refresher however
    /// `body` ends.
    ///
    /// A refresher the case leaves running holds a task after the case
    /// returns, which its own `deinit` refuses in a debug build. So the stop
    /// stands here, on both exits, and no case carries it.
    ///
    /// - Parameters:
    ///   - name: The name of the server, and so the noun its verbs render
    ///     under.
    ///   - scripted: The scripted server to serve on the far end, which this
    ///     method keeps alive for the whole case.
    ///   - body: The case, given the ground.
    /// - Throws: What `makeGround(named:serving:)` or `body` throws.
    private static func withStartedRefresher(
        named name: String,
        serving scripted: ScriptedServer,
        _ body: (Ground) async throws -> Void
    ) async throws {
        let ground = try await makeGround(named: name, serving: scripted)
        ground.refresher.start()
        var thrown: (any Error)?
        do {
            try await body(ground)
        } catch {
            thrown = error
        }
        await ground.refresher.stop()
        withExtendedLifetime(scripted) {}
        if let thrown {
            throw thrown
        }
    }

    /// Waits until `staging` has recorded at least `count` stages.
    ///
    /// - Parameters:
    ///   - count: The number of stages to wait for.
    ///   - staging: The staging to read.
    /// - Throws: `TestPoll.ConditionNeverHeld` when the deadline passes.
    private static func waitForStages(
        _ count: Int, on staging: RecordingStaging
    ) async throws {
        try await TestPoll.waitUntil("the refresher staged \(count) registries") {
            staging.count >= count
        }
    }

    /// Publishes `tool` on `scripted` and tells the client the list changed.
    ///
    /// - Parameters:
    ///   - tool: The tool to publish.
    ///   - scripted: The scripted server to publish on.
    /// - Throws: What the notification throws.
    private static func publish(_ tool: ScriptedTool, on scripted: ScriptedServer) async throws {
        await scripted.addTool(tool)
        try await scripted.emitToolListChangedBurst(count: oneNotification)
    }

    /// The rendered path of the echo verb of the server named `name`.
    ///
    /// - Parameters:
    ///   - verb: The tool name the server declares.
    ///   - name: The name of the server, and so the noun.
    /// - Returns: The `tools.<noun>.<verb>` path, without its `tools.` prefix.
    private static func path(of verb: String, on name: String) -> String {
        "\(name).\(verb)"
    }

    /// The log lines the rebuild of the server named `name` wrote since
    /// `start`.
    ///
    /// The server name is part of the line, so a case reads back only its own
    /// lines however many suites run beside it.
    ///
    /// - Parameters:
    ///   - name: The name of the server whose lines to read.
    ///   - start: The instant to read from.
    /// - Returns: The matching lines, in emission order.
    /// - Throws: What the log store throws when it cannot be opened or read.
    private static func rebuildFailureLines(
        of name: String, since start: Date
    ) throws -> [String] {
        let marker = "\(SurfaceRefresher.rebuildFailureLogPrefix) server=\(name)"
        return try multitoolLogMessages(since: start).filter { $0.hasPrefix(marker) }
    }

    // MARK: - A tool the server adds

    @Test("a tool the server adds reaches the surface at the next tick, and a snippet calls it")
    func anAddedToolReachesTheSurfaceAtTheNextTick() async throws {
        let scripted = ScriptedServer(name: Self.dynamicServerName)
        await scripted.startDynamicToolsetScenario()

        try await Self.withStartedRefresher(named: Self.dynamicServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)
            #expect(try await helpPaths(of: ground.runCode) == [Self.counterPath])

            // Stage one of the scenario adds the greeter and sends
            // `tools/list_changed`. No host action follows it.
            try await Self.waitForStages(Self.stagesAfterOneChange, on: ground.staging)
            await ground.runCode.turnWillBegin()

            #expect(try await helpPaths(of: ground.runCode) == [Self.counterPath, Self.greeterPath])
            let echoed = try await ground.runCode.call(
                arguments: RunCodeArguments(code: Self.greeterSnippet))
            #expect(echoed.contains(Self.greeting), "the greeter answered: \(echoed)")
        }
    }

    // MARK: - A tool the server removes

    @Test("a tool the server removes leaves the surface at the next tick, and a snippet gets the repair hint")
    func aRemovedToolLeavesTheSurfaceAtTheNextTick() async throws {
        let scripted = ScriptedServer(name: Self.dynamicServerName)
        await scripted.startDynamicToolsetScenario()

        try await Self.withStartedRefresher(named: Self.dynamicServerName, serving: scripted) { ground in
            // The three stages of the scenario are add, re-schema, remove.
            try await Self.waitForStages(Self.stagesAfterThreeChanges, on: ground.staging)
            await ground.runCode.turnWillBegin()

            #expect(try await helpPaths(of: ground.runCode) == [Self.counterPath])
            let answer = try await ground.runCode.call(
                arguments: RunCodeArguments(code: Self.greeterSnippet))
            #expect(answer.contains("tools.\(Self.greeterPath) \(UnknownToolHint.missingPathPhrase)"))
        }
    }

    // MARK: - A burst of changes, and one swap

    @Test("three changes before one tick give one swap")
    func threeChangesBeforeOneTickGiveOneSwap() async throws {
        let scripted = ScriptedServer(name: Self.burstServerName)
        await scripted.addEchoTool()
        let echoPath = Self.path(of: ScriptedServer.echoToolName, on: Self.burstServerName)

        try await Self.withStartedRefresher(named: Self.burstServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)

            try await Self.publish(ScriptedServer.echoTool(named: Self.alphaToolName), on: scripted)
            try await Self.waitForStages(Self.stagesAfterOneChange, on: ground.staging)
            try await Self.publish(ScriptedServer.echoTool(named: Self.betaToolName), on: scripted)
            try await Self.waitForStages(Self.stagesAfterTwoChanges, on: ground.staging)
            try await Self.publish(ScriptedServer.echoTool(named: Self.gammaToolName), on: scripted)
            try await Self.waitForStages(Self.stagesAfterThreeChanges, on: ground.staging)

            // Three registries are staged, and not one of them is current:
            // only a tick swaps.
            #expect(try await helpPaths(of: ground.runCode) == [echoPath])

            await ground.runCode.turnWillBegin()

            #expect(
                try await helpPaths(of: ground.runCode) == [
                    echoPath,
                    Self.path(of: Self.alphaToolName, on: Self.burstServerName),
                    Self.path(of: Self.betaToolName, on: Self.burstServerName),
                    Self.path(of: Self.gammaToolName, on: Self.burstServerName),
                ])
        }
    }

    // MARK: - A rebuild that throws

    @Test("a rebuild that throws keeps the old surface, logs one line, and the next snapshot tries again")
    func aFailedRebuildKeepsTheOldSurfaceAndTriesAgain() async throws {
        let scripted = ScriptedServer(name: Self.failureServerName)
        await scripted.addEchoTool()
        let echoPath = Self.path(of: ScriptedServer.echoToolName, on: Self.failureServerName)
        let start = Date()

        try await Self.withStartedRefresher(named: Self.failureServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)

            // The verb fails the renderer's own identifier check, so the
            // rebuild throws and nothing is staged.
            try await Self.publish(
                ScriptedServer.echoTool(named: Self.illegalVerb), on: scripted)
            try await TestPoll.waitUntil(
                "the failed rebuild reached the log", before: Self.logReadbackDeadline
            ) {
                let lines = try? Self.rebuildFailureLines(
                    of: Self.failureServerName, since: start)
                return (lines?.count ?? 0) >= Self.oneLogLine
            }
            try await Task.sleep(for: Self.noFurtherStageSettleDelay)
            await ground.runCode.turnWillBegin()

            #expect(ground.staging.count == Self.stagesAfterConnect)
            #expect(
                try Self.rebuildFailureLines(of: Self.failureServerName, since: start).count
                    == Self.oneLogLine)
            #expect(try await helpPaths(of: ground.runCode) == [echoPath])

            // The next snapshot tries again, and it renders.
            await scripted.removeTool(named: Self.illegalVerb)
            try await Self.publish(
                ScriptedServer.echoTool(named: Self.recoveredToolName), on: scripted)
            try await Self.waitForStages(Self.stagesAfterOneChange, on: ground.staging)
            await ground.runCode.turnWillBegin()

            #expect(
                try await helpPaths(of: ground.runCode) == [
                    echoPath, Self.path(of: Self.recoveredToolName, on: Self.failureServerName),
                ])
        }
    }

    // MARK: - The end of the watch

    @Test("stop ends the watch task, and nothing stages after it")
    func stopEndsTheWatchTask() async throws {
        let scripted = ScriptedServer(name: Self.stoppedServerName)
        await scripted.addEchoTool()

        try await Self.withStartedRefresher(named: Self.stoppedServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)
            #expect(ground.refresher.isWatching)

            // `stop()` returns only once the task it cancelled has ended, so
            // the reading below is a fact and not a race.
            await ground.refresher.stop()

            #expect(!ground.refresher.isWatching)
            try await Self.publish(ScriptedServer.echoTool(named: Self.alphaToolName), on: scripted)
            try await TestPoll.waitUntil("the server re-listed the added tool") {
                await ground.server.tool(named: Self.alphaToolName) != nil
            }
            try await Task.sleep(for: Self.noFurtherStageSettleDelay)

            #expect(ground.staging.count == Self.stagesAfterConnect)
        }
    }

    @Test("a session mounted with no refresher leaves no task behind, and its surface never moves")
    func aSessionWithNoRefresherNeverMoves() async throws {
        let scripted = ScriptedServer(name: Self.unwatchedServerName)
        await scripted.addEchoTool()
        let echoPath = Self.path(of: ScriptedServer.echoToolName, on: Self.unwatchedServerName)
        let ground = try await Self.makeGround(named: Self.unwatchedServerName, serving: scripted)

        // No refresher is started. `makeSessionToolsAndStaging` starts no task
        // of its own, so nothing watches the stream.
        try await Self.publish(ScriptedServer.echoTool(named: Self.alphaToolName), on: scripted)
        try await TestPoll.waitUntil("the server re-listed the added tool") {
            await ground.server.tool(named: Self.alphaToolName) != nil
        }
        await ground.runCode.turnWillBegin()

        #expect(ground.staging.count == 0)
        #expect(try await helpPaths(of: ground.runCode) == [echoPath])
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A late server

    @Test("addServer puts a late server's verbs on the surface at the next tick")
    func addServerPutsTheLateVerbsOnTheSurface() async throws {
        let scripted = ScriptedServer(name: Self.firstServerName)
        await scripted.addEchoTool()
        let lateScripted = ScriptedServer(name: Self.lateServerName)
        await lateScripted.addEchoTool()

        try await Self.withStartedRefresher(named: Self.firstServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)
            let late = try await MCPTestSupport.connectedMCPServer(
                to: lateScripted, over: .inMemory, name: Self.lateServerName, clock: ManualClock())

            try await ground.refresher.addServer(late)
            await ground.runCode.turnWillBegin()

            #expect(
                try await helpPaths(of: ground.runCode) == [
                    Self.path(of: ScriptedServer.echoToolName, on: Self.firstServerName),
                    Self.path(of: ScriptedServer.echoToolName, on: Self.lateServerName),
                ])
            withExtendedLifetime(lateScripted) {}
        }
    }

    @Test("a late server is watched for its own changes")
    func aLateServerIsWatchedForItsOwnChanges() async throws {
        let scripted = ScriptedServer(name: Self.firstServerName)
        await scripted.addEchoTool()
        let lateScripted = ScriptedServer(name: Self.lateServerName)
        await lateScripted.addEchoTool()

        try await Self.withStartedRefresher(named: Self.firstServerName, serving: scripted) { ground in
            try await Self.waitForStages(Self.stagesAfterConnect, on: ground.staging)
            let late = try await MCPTestSupport.connectedMCPServer(
                to: lateScripted, over: .inMemory, name: Self.lateServerName, clock: ManualClock())
            try await ground.refresher.addServer(late)

            try await Self.publish(
                ScriptedServer.echoTool(named: Self.alphaToolName), on: lateScripted)
            try await TestPoll.waitUntil("the late server's change reached the surface") {
                await ground.runCode.turnWillBegin()
                let paths = try? await helpPaths(of: ground.runCode)
                return paths?.contains(Self.path(of: Self.alphaToolName, on: Self.lateServerName))
                    ?? false
            }
            withExtendedLifetime(lateScripted) {}
        }
    }
}
