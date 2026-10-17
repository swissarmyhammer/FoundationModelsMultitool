import Foundation
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `MultiTool.RegistrySource.rebuildRegistry()` — the first
/// half of rebuild-and-swap. eventplan.md § "Consolidation of the siblings":
/// "A late server, a reconnect, or an MCP `tools/list_changed` starts a full
/// rebuild. MultiTool renders the new registry complete at the side."
///
/// Four facts carry this suite:
///
/// 1. A rebuild after a server adds a tool gives a `Registry` with the new
///    verb, and the first `Registry` value is unchanged.
/// 2. A rebuild after a server removes a tool gives a `Registry` without it.
/// 3. A rebuild that would now collide throws, and the caller keeps the old
///    `Registry`.
/// 4. The shell and files verbs are the same instances across a rebuild: the
///    `ShellState` store and the `FileContext` of the first build are the
///    ones the rebuild renders.
///
/// The add and remove cases run over the dynamic toolset scenario of the
/// test server, whose three stages add, re-schema and remove a tool. Each
/// case runs a stage with `advanceDynamicToolsetScenario()`, thus no timer
/// decides what the catalog holds when the case reads it.
/// Every server sleeps on a `ManualClock`, so the coalesce window of a
/// `tools/list_changed` re-list takes no real time — the convention of
/// `LiveCatalogTests`.
@Suite("RegistryRebuildTests")
struct RegistryRebuildTests {

    // MARK: - Shared test constants

    /// Owns the temporary directories this test makes, so they go away when
    /// the test ends and they do not collect in `$TMPDIR`.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test, so a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "registry-rebuild-tests"

    /// The name every server of this suite is constructed with, and so the
    /// noun its verbs render under.
    private static let serverName = "dynamic"

    /// The rendered path of the tool the dynamic scenario starts with.
    private static let counterPath = "\(serverName).\(ScriptedServer.dynamicToolsetReschemadToolName)"

    /// The rendered path of the tool the dynamic scenario adds and later
    /// removes.
    private static let greeterPath = "\(serverName).\(ScriptedServer.dynamicToolsetVanishingToolName)"

    /// The rendered path of the echo tool of a plain scripted server.
    private static let echoPath = "\(serverName).\(ScriptedServer.echoToolName)"

    /// A tool name that is not a legal TypeScript identifier, which a server
    /// may publish and the renderer must refuse.
    private static let illegalVerb = "bad verb!"

    /// The rendered path of the `getLines` verb of the shell.
    private static let shellGetLinesPath = "shell.getLines"

    /// The rendered path of the `read` verb of the files capability.
    private static let filesReadPath = "files.read"

    /// How many `tools/list_changed` notifications a plain server sends after
    /// one mutation. One is enough; the re-list coalesces a burst anyway.
    private static let oneNotification = 1

    /// How many `tools/list_changed` notifications two stages of the dynamic
    /// scenario send: one for each stage.
    private static let twoStageNotifications = 2

    /// How many entries the catalog holds after the echo tool is published a
    /// second time.
    private static let echoToolCountAfterDuplicate = 2

    // MARK: - The ground of one test

    /// A scripted server running the dynamic scenario, beside a server named
    /// ``serverName`` connected against it over the in-memory transport.
    ///
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connectedDynamicServer() async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer(name: serverName)
        await scripted.startDynamicToolsetScenario()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: serverName, clock: ManualClock())
        return (scripted, server)
    }

    /// A scripted server serving the echo tool, beside a server named
    /// ``serverName`` connected against it over the in-memory transport.
    ///
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connectedEchoServer() async throws -> (scripted: ScriptedServer, server: MCPServer) {
        let scripted = ScriptedServer(name: serverName)
        await scripted.addEchoTool()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: serverName, clock: ManualClock())
        return (scripted, server)
    }

    /// The error ``waitUntilCatalog(of:after:notifications:satisfies:)``
    /// throws when `catalogUpdates` ends before a snapshot meets the
    /// condition.
    private struct CatalogUpdatesEnded: Error {}

    /// The counts of one server at one point: the `tools/list_changed`
    /// notifications it counted, and the snapshots it emitted.
    private struct CatalogMark {
        /// The count of `tools/list_changed` notifications.
        let generation: Int

        /// The count of emitted snapshots: the epoch of the last one.
        let epoch: Int
    }

    /// The counts of `server` now, read before a change of its catalog.
    ///
    /// - Parameter server: The server to read.
    /// - Returns: The counts.
    private static func mark(_ server: MCPServer) async -> CatalogMark {
        CatalogMark(generation: await server.toolListChangedGeneration, epoch: await server.catalogEpoch)
    }

    /// Waits until the re-list that `notifications` more notifications after
    /// `mark` start ended, and then reads the `catalogUpdates` snapshots of
    /// `server` until one snapshot meets `condition`.
    ///
    /// The stream finishes only when the server goes away, thus a read for
    /// a snapshot that never comes would not end. The test thus first waits
    /// for the end of the re-list, and fails at once unless the re-list
    /// emitted a snapshot after `mark` whose catalog meets `condition`. Only
    /// then it reads the stream, and that read ends on the snapshot.
    ///
    /// The stream holds every snapshot since the server was made, and no
    /// other consumer reads it in this suite (this suite starts no
    /// `SurfaceRefresher`). Thus each call reads on from the snapshot after
    /// the last one an earlier call read, and it does not miss a snapshot.
    ///
    /// - Parameters:
    ///   - server: The server whose snapshots to read.
    ///   - mark: The counts of `server` before the change.
    ///   - notifications: How many notifications the change sent.
    ///   - condition: The condition one snapshot must meet.
    /// - Throws: When the re-list emitted no such snapshot, or
    ///   ``CatalogUpdatesEnded`` when the stream ends first.
    private static func waitUntilCatalog(
        of server: MCPServer, after mark: CatalogMark, notifications: Int = oneNotification,
        satisfies condition: (MCPToolCatalog) -> Bool
    ) async throws {
        await MCPTestSupport.waitForRelist(of: server, reaching: mark.generation + notifications)
        let catalog = try await server.catalog
        let epoch = await server.catalogEpoch
        try #require(
            epoch > mark.epoch && condition(catalog),
            "the re-list emitted no snapshot that meets the condition: \(catalog)")
        for await snapshot in await server.catalogUpdates where condition(snapshot) {
            return
        }
        throw CatalogUpdatesEnded()
    }

    /// Waits until the re-list after `mark` ended, and then reads the
    /// `catalogUpdates` snapshots of `server` until one snapshot does or
    /// does not hold a tool named `name` — see
    /// ``waitUntilCatalog(of:after:notifications:satisfies:)``.
    ///
    /// - Parameters:
    ///   - server: The server whose snapshots to read.
    ///   - mark: The counts of `server` before the change.
    ///   - notifications: How many notifications the change sent.
    ///   - name: The tool name to look for.
    ///   - present: Whether to wait for the tool to appear or to vanish.
    /// - Throws: When the re-list emitted no such snapshot, or
    ///   ``CatalogUpdatesEnded`` when the stream ends first.
    private static func waitUntilCatalog(
        of server: MCPServer, after mark: CatalogMark, notifications: Int = oneNotification,
        holds name: String, present: Bool
    ) async throws {
        try await waitUntilCatalog(of: server, after: mark, notifications: notifications) { snapshot in
            snapshot.tools.contains { $0.name == name } == present
        }
    }

    /// The paths of every entry of `registry`, in render order.
    ///
    /// - Parameter registry: The registry to read.
    /// - Returns: The paths.
    private static func paths(of registry: MultiTool.Registry) -> [String] {
        registry.surface.entries.map(\.path)
    }

    /// Publishes `tool` on `scripted` and tells the client the list changed,
    /// then waits until the catalog of `server` holds `tool`.
    ///
    /// - Parameters:
    ///   - tool: The tool to publish.
    ///   - scripted: The scripted server to publish on.
    ///   - server: The connected server whose catalog re-lists.
    /// - Throws: What the notification or the wait throws.
    private static func publish(
        _ tool: ScriptedTool, on scripted: ScriptedServer, seenBy server: MCPServer
    ) async throws {
        let before = await mark(server)
        await scripted.addTool(tool)
        try await scripted.emitToolListChangedBurst(count: oneNotification)
        try await waitUntilCatalog(of: server, after: before, holds: tool.definition.name, present: true)
    }

    // MARK: - Add and remove

    @Test("rebuildRegistry() after the scenario adds a tool gives the new verb, and the first registry is unchanged")
    func rebuildAfterAnAddGivesTheNewVerbAndKeepsTheFirstRegistry() async throws {
        let (scripted, server) = try await Self.connectedDynamicServer()
        try await MCPTestSupport.withConnection(of: server) {
            let builder = try await MultiTool.Builder().withMCP(servers: [server])
            let first = try builder.buildRegistry()
            let source = builder.registrySource
            #expect(Self.paths(of: first) == [Self.counterPath])

            // The first stage adds the greeter.
            let beforeAdd = await Self.mark(server)
            #expect(await scripted.advanceDynamicToolsetScenario())
            try await Self.waitUntilCatalog(
                of: server, after: beforeAdd, holds: ScriptedServer.dynamicToolsetVanishingToolName, present: true)
            let rebuilt = try await source.rebuildRegistry()

            #expect(Self.paths(of: rebuilt) == [Self.counterPath, Self.greeterPath])
            #expect(rebuilt.tools[Self.greeterPath] != nil)
            // The first value is untouched: the rebuild rendered at the side.
            #expect(Self.paths(of: first) == [Self.counterPath])
            #expect(first.tools[Self.greeterPath] == nil)
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("rebuildRegistry() after the scenario removes a tool gives a registry without it")
    func rebuildAfterARemoveDropsTheVerb() async throws {
        let (scripted, server) = try await Self.connectedDynamicServer()
        try await MCPTestSupport.withConnection(of: server) {
            let builder = try await MultiTool.Builder().withMCP(servers: [server])
            let source = builder.registrySource

            // The first stage adds the greeter.
            let beforeAdd = await Self.mark(server)
            #expect(await scripted.advanceDynamicToolsetScenario())
            try await Self.waitUntilCatalog(
                of: server, after: beforeAdd, holds: ScriptedServer.dynamicToolsetVanishingToolName, present: true)
            let withGreeter = try await source.rebuildRegistry()
            #expect(withGreeter.tools[Self.greeterPath] != nil)

            // The second stage re-schemas the counter, and the third removes the
            // greeter. Each stage sends one notification.
            let beforeRemove = await Self.mark(server)
            #expect(await scripted.advanceDynamicToolsetScenario())
            #expect(await scripted.advanceDynamicToolsetScenario())
            try await Self.waitUntilCatalog(
                of: server, after: beforeRemove, notifications: Self.twoStageNotifications,
                holds: ScriptedServer.dynamicToolsetVanishingToolName, present: false)
            let withoutGreeter = try await source.rebuildRegistry()

            #expect(Self.paths(of: withoutGreeter) == [Self.counterPath])
            #expect(withoutGreeter.tools[Self.greeterPath] == nil)
            // The earlier value still holds the verb: nothing changed in place.
            #expect(withGreeter.tools[Self.greeterPath] != nil)
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A rebuild that collides

    @Test("a rebuild whose server now publishes one verb two times throws MultiToolBuilderError, and the caller keeps the old registry")
    func rebuildThatCollidesThrowsAndKeepsTheOldRegistry() async throws {
        let (scripted, server) = try await Self.connectedEchoServer()
        try await MCPTestSupport.withConnection(of: server) {
            let builder = try await MultiTool.Builder().withMCP(servers: [server])
            let first = try builder.buildRegistry()
            let source = builder.registrySource

            // The scripted server appends without a name check, so a second echo
            // tool makes `tools/list` publish the echo verb two times — two tools
            // at one path, which is the `.duplicateName` collision of the build.
            let before = await Self.mark(server)
            await scripted.addTool(ScriptedServer.echoTool())
            try await scripted.emitToolListChangedBurst(count: Self.oneNotification)
            try await Self.waitUntilCatalog(of: server, after: before) { snapshot in
                snapshot.tools.count == Self.echoToolCountAfterDuplicate
            }

            await #expect {
                try await source.rebuildRegistry()
            } throws: { error in
                guard let builderError = error as? MultiToolBuilderError else { return false }
                return builderError.kind == .duplicateName && builderError.name == ScriptedServer.echoToolName
            }
            #expect(Self.paths(of: first) == [Self.echoPath])
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a rebuild whose server now publishes an illegal verb throws, and the caller keeps the old registry")
    func rebuildWithAnIllegalVerbThrowsAndKeepsTheOldRegistry() async throws {
        let (scripted, server) = try await Self.connectedEchoServer()
        try await MCPTestSupport.withConnection(of: server) {
            let builder = try await MultiTool.Builder().withMCP(servers: [server])
            let first = try builder.buildRegistry()
            let source = builder.registrySource

            try await Self.publish(
                ScriptedServer.echoTool(named: Self.illegalVerb), on: scripted, seenBy: server)

            // The verb fails the renderer's own identifier check, which the build
            // propagates unchanged — the posture `buildRegistry()` documents.
            await #expect(throws: ToolAPIRendererError.self) {
                try await source.rebuildRegistry()
            }
            #expect(Self.paths(of: first) == [Self.echoPath])
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Shell and files identity

    @Test("the shell and files verbs are the same instances across a rebuild")
    func shellAndFilesVerbsHoldTheirInstancesAcrossARebuild() async throws {
        let (scripted, server) = try await Self.connectedEchoServer()
        try await MCPTestSupport.withConnection(of: server) {
            let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            let storeDirectory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            let builder = try await MultiTool.Builder()
                .withShell(storeDirectory: storeDirectory)
                .withFiles(root: root)
                .withMCP(servers: [server])
            let first = try builder.buildRegistry()

            let rebuilt = try await builder.rebuildRegistry()

            let firstGetLines = try #require(first.tools[Self.shellGetLinesPath] as? GetLines)
            let rebuiltGetLines = try #require(rebuilt.tools[Self.shellGetLinesPath] as? GetLines)
            #expect(firstGetLines.state === rebuiltGetLines.state)

            let firstRead = try #require(first.tools[Self.filesReadPath] as? Read)
            let rebuiltRead = try #require(rebuilt.tools[Self.filesReadPath] as? Read)
            #expect(firstRead.context === rebuiltRead.context)

            // The MCP verb is a new instance over the same server: the catalog
            // was read again.
            let firstEcho = try #require(first.tools[Self.echoPath] as? MCPTool)
            let rebuiltEcho = try #require(rebuilt.tools[Self.echoPath] as? MCPTool)
            #expect(firstEcho.server === rebuiltEcho.server)
            #expect(Self.paths(of: rebuilt) == Self.paths(of: first))
        }
        withExtendedLifetime(scripted) {}
    }
}
