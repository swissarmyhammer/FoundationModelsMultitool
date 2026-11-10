// `SandboxedRegistryNoProcessTests` — a registry in `sandboxed` mode starts
// no process (MT-15).
//
// Only two code paths of Multitool start a child process: `ShellRunner` and
// `StdioServerProcess`. This suite makes a `sandboxed` registry with each
// capability that `sandboxed` mode permits, and then examines it two ways:
//
// - Structural checks: no registration is a shell capability, no noun is
//   `shell`, no MCP capability connected over a child process, and the pool of
//   the builder holds no `StdioServerProcess`.
// - A run check: one `runCode` snippet calls one read verb of each noun, and
//   the spawn observer of the builder gets no call.
//
// The spawn observer belongs to one builder. Other suites start processes in
// parallel, but they cannot change the count of this observer. Thus no test
// here counts global PIDs, sleeps, or waits for a time. An `open` test proves
// that the observer works: one `shell.execute` of `true` gives one call.
//
// Each test gives a `.fixed(...)` probe. A `.live` probe reads the test
// process, and the result then changes with the machine.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("SandboxedRegistryNoProcess", .ownsTemporaryDirectories)
struct SandboxedRegistryNoProcessTests {
    /// The probe of a process in the App Sandbox.
    private static let sandboxedProcess = SandboxProbe.fixed(true)

    /// The probe of a process out of the App Sandbox.
    private static let openProcess = SandboxProbe.fixed(false)

    /// The name of the temporary directories of this suite.
    private static let directoryName = "sandboxed-registry-no-process"

    /// The name of the MCP server of this suite, which is also its noun.
    private static let serverName = "noProcessServer"

    /// The noun of the shell capability.
    private static let shellNoun = "shell"

    /// The file in the root that the snippet reads.
    private static let noteFileName = "note.txt"

    /// The text of ``noteFileName``.
    private static let noteText = "no process"

    /// The URL of the one hit that the stub search backend gives.
    private static let hitURL = "https://hit.example/1"

    /// The value that the snippet returns after its last call. A snippet
    /// that stopped at an error does not return it.
    private static let completionMarker = "every read verb returned"

    /// The snippet that calls one read verb of each noun of the sandboxed
    /// registry, and then returns ``completionMarker``.
    private static let readEachNounSnippet = """
        await tools.files.read(\(ToolAPIRenderer.jsStringLiteral(noteFileName)));
        await tools.git.status({});
        await tools.environment.variables({});
        await tools.snapshots.list({});
        await tools.web.search({ query: \(ToolAPIRenderer.jsStringLiteral(WebRun.query)) });
        await tools.\(serverName).\(ScriptedServer.echoToolName)({ \(ScriptedServer.echoTextArgument): "hi" });
        return \(ToolAPIRenderer.jsStringLiteral(completionMarker));
        """

    /// The snippet that runs `true` one time through the shell.
    private static let shellTrueSnippet = #"return await tools.shell.execute({ command: "true" });"#

    // MARK: - The ground of one test

    /// A `sandboxed` builder with each capability that `sandboxed` mode
    /// permits, and the values that must stay alive while a test runs.
    private struct SandboxedGround {
        /// The builder. Its spawn observer is ``spawns``.
        let builder: MultiTool.Builder

        /// The count of the calls of the spawn observer of ``builder``.
        let spawns: CallCounter

        /// The scripted MCP server behind the in-memory transport.
        let scripted: ScriptedServer

        /// The stub that answers each web request, thus no request goes to
        /// the network.
        let stub: WebStub
    }

    /// Makes a `sandboxed` builder with files, git, snapshots, environment,
    /// web over a stub search backend, and one MCP server on an in-memory
    /// transport.
    ///
    /// - Returns: the builder and the values that must stay alive.
    /// - Throws: what the connect of the MCP server, `withMCP(servers:)`, the
    ///   write of the note file, or the URL of the stub search throws.
    private static func makeSandboxedGround() async throws -> SandboxedGround {
        let root = TestSupport.makeTemporaryDirectory(named: directoryName)
        try noteText.write(to: root.appendingPathComponent(noteFileName), atomically: true, encoding: .utf8)
        let snapshots = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: directoryName))
        let stub = WebStub(routes: [try WebRun.searchURL(): WebRun.searchReply(hitting: [hitURL])])
        let (scripted, server) = try await MCPTestSupport.connectedLoopbackMCPServer(
            over: .inMemory, name: serverName)
        let spawns = CallCounter()
        let builder = try await MultiTool.Builder(
            mode: .sandboxed, sandboxProbe: sandboxedProcess, spawnObserver: { spawns.increment() }
        )
        .withFiles(root: root)
        .withGit(root: root)
        .withEnvironment(context: InjectedEnvironment.context())
        .withWeb(
            configuration: WebConfiguration(providers: [.braveAPI(.literal(WebRun.testKey))]),
            sessionConfiguration: stub.sessionConfiguration, resolver: PublicHostResolver())
        .withCapability(SnapshotsCapability(store: snapshots))
        .withMCP(servers: [server])
        return SandboxedGround(builder: builder, spawns: spawns, scripted: scripted, stub: stub)
    }

    /// The capabilities that `builder` recorded, in registration order.
    ///
    /// - Parameter builder: the builder to read.
    /// - Returns: each recorded capability. A tool that is not a capability
    ///   is not in the list.
    private static func capabilities(of builder: MultiTool.Builder) -> [any Capability] {
        builder.registrySource.registrations.compactMap { registration in
            guard case .capability(let capability) = registration else { return nil }
            return capability
        }
    }

    /// The nouns of `registry`, in sorted order.
    ///
    /// - Parameter registry: the registry to read.
    /// - Returns: the group of each entry, one time each.
    private static func nouns(of registry: MultiTool.Registry) -> [String] {
        Set(registry.surface.entries.compactMap(\.group)).sorted()
    }

    // MARK: - The structure

    @Test("a sandboxed registry records no shell capability")
    func sandboxedRegistryRecordsNoShellCapability() async throws {
        let ground = try await Self.makeSandboxedGround()

        #expect(!Self.capabilities(of: ground.builder).contains { $0 is ShellCapability })
    }

    @Test("a sandboxed registry has no shell noun")
    func sandboxedRegistryHasNoShellNoun() async throws {
        let ground = try await Self.makeSandboxedGround()

        let registry = try ground.builder.buildRegistry()

        #expect(!Self.nouns(of: registry).contains(Self.shellNoun), "nouns were: \(Self.nouns(of: registry))")
    }

    @Test("a sandboxed registry has no MCP capability that connected over a child process")
    func sandboxedRegistryHasNoChildProcessServer() async throws {
        let ground = try await Self.makeSandboxedGround()

        let servers = Self.capabilities(of: ground.builder).compactMap { $0 as? MCPCapability }

        #expect(!servers.isEmpty && servers.allSatisfy { !$0.connectsOverChildProcess })
    }

    @Test("the server pool of a sandboxed builder holds no StdioServerProcess")
    func sandboxedPoolHoldsNoStdioServerProcess() async throws {
        let ground = try await Self.makeSandboxedGround()

        #expect(await ground.builder.serverPool.processCount == 0)
    }

    // MARK: - The run

    @Test("a read verb of each noun of a sandboxed registry starts no process")
    func sandboxedReadVerbsStartNoProcess() async throws {
        let ground = try await Self.makeSandboxedGround()
        let registry = try ground.builder.buildRegistry()

        let output = try await runSnippet(Self.readEachNounSnippet, over: registry)

        try #require(output.contains(Self.completionMarker), "output was: \(output)")
        #expect(ground.spawns.count == 0)
        withExtendedLifetime(ground) {}
    }

    @Test("in open mode one shell.execute of true gives one call to the spawn observer")
    func openShellExecuteCallsTheSpawnObserverOneTime() async throws {
        let spawns = CallCounter()
        let store = try ShellStore(
            storeDirectory: TestSupport.makeTemporaryDirectory(named: Self.directoryName)
                .appendingPathComponent(TestScratch.shellStoreDirectoryName))
        let registry = try MultiTool.Builder(
            mode: .open, sandboxProbe: Self.openProcess, spawnObserver: { spawns.increment() }
        )
        .withShell(store: store, defaultWorkingDirectory: TestSupport.makeTemporaryDirectory(named: Self.directoryName))
        .buildRegistry()

        _ = try await runSnippet(Self.shellTrueSnippet, over: registry)

        #expect(spawns.count == 1)
    }
}
