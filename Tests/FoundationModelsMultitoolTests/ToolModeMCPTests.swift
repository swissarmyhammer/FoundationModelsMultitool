// `ToolModeMCPTests` — the `ToolMode` of the MCP servers over stdio (D128
// (d), MT-15).
//
// In `sandboxed` mode no stdio MCP server can start. The host must not start
// one, and Multitool adds two hard guards:
//
// - A `StdioServerProcess` in `sandboxed` mode throws `notAvailable` before
//   it spawns a process.
// - `buildRegistry()` in `sandboxed` mode throws `notAvailable` for a server
//   that connected over a `StdioServerProcess`.
//
// An MCP server on a transport that is not a child process (HTTP or in
// memory) registers in both modes.
//
// Each test gives a `.fixed(...)` probe. A `.live` probe reads the test
// process, and the result then changes with the machine. No test counts the
// child processes of the test process: other suites start child processes
// in parallel. A private `ProcessRegistry` shows that no spawn occurred.

import Foundation
import FoundationModelsExtras
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("ToolModeMCP")
struct ToolModeMCPTests {
    /// The probe of a process in the App Sandbox.
    private static let sandboxedProcess = SandboxProbe.fixed(true)

    /// The probe of a process out of the App Sandbox.
    private static let openProcess = SandboxProbe.fixed(false)

    /// A command that is present on each macOS machine. A test in
    /// `sandboxed` mode must never start it.
    private static let catCommand = "/bin/cat"

    /// The name of each server and each process of this suite.
    private static let serverName = "toolModeServer"

    /// The error that a `sandboxed` start of a `StdioServerProcess` gives.
    private static let processNotAvailable = StdioServerProcess.StdioServerProcessError.notAvailable(
        mode: .sandboxed)

    /// The error that `buildRegistry()` gives for a stdio server in
    /// `sandboxed` mode, as its kind and its name.
    private static let serverNotAvailable = (MultiToolBuilderError.Kind.notAvailable(mode: .sandboxed), serverName)

    /// A `StdioServerProcess` for `/bin/cat` in `sandboxed` mode.
    ///
    /// - Parameter registry: the registry that records each spawn.
    /// - Returns: the process. It has not started.
    private static func makeSandboxedCat(registry: ProcessRegistry) throws -> StdioServerProcess {
        try StdioServerProcess(command: catCommand, name: serverName, registry: registry, mode: .sandboxed)
    }

    /// The nouns of `registry`, in sorted order.
    ///
    /// - Parameter registry: the registry to read.
    /// - Returns: the group of each entry, one time each.
    private static func nouns(of registry: MultiTool.Registry) -> [String] {
        Set(registry.surface.entries.compactMap(\.group)).sorted()
    }

    /// Connects a server to the echo test server over a `StdioServerProcess`
    /// in `open` mode, runs `body`, and then disconnects the server.
    ///
    /// The disconnect also stops the subprocess, also when `body` throws.
    ///
    /// - Parameter body: the work of the test on the connected server.
    /// - Returns: what `body` returned.
    /// - Throws: what the connect or `body` threw.
    private static func withStdioServer<Result>(
        _ body: (MCPServer) async throws -> Result
    ) async throws -> Result {
        let stdio = try StdioServerProcess(
            command: TestServerLocator.executableURL().path,
            args: [ServerMode.flagName, ServerMode.echo.rawValue],
            name: serverName, registry: ProcessRegistry())
        let server = MCPTestSupport.makeServer(name: serverName)
        try await server.connect(via: stdio.respawn)
        return try await MCPTestSupport.withConnection(of: server) { try await body(server) }
    }

    /// The error that `buildRegistry()` of a `sandboxed` builder gives for a
    /// server that connected over a `StdioServerProcess`.
    ///
    /// - Returns: the error of the builder.
    /// - Throws: what the connect threw, or a failed requirement when
    ///   `buildRegistry()` throws no `MultiToolBuilderError`.
    private static func sandboxedStdioRefusal() async throws -> MultiToolBuilderError {
        try await withStdioServer { server in
            let builder = try await MultiTool.Builder(mode: .sandboxed, sandboxProbe: sandboxedProcess)
                .withMCP(servers: [server])
            return try #require(throws: MultiToolBuilderError.self) { try builder.buildRegistry() }
        }
    }

    // MARK: - The process

    @Test("a sandboxed start of a StdioServerProcess throws notAvailable")
    func sandboxedStartThrowsNotAvailable() async throws {
        let stdio = try Self.makeSandboxedCat(registry: ProcessRegistry())

        await #expect(throws: Self.processNotAvailable) { _ = try await stdio.respawn() }
    }

    @Test("a sandboxed start of a StdioServerProcess registers no process")
    func sandboxedStartRegistersNoProcess() async throws {
        let registry = ProcessRegistry()
        let stdio = try Self.makeSandboxedCat(registry: registry)

        _ = try? await stdio.respawn()

        #expect(registry.registeredPids.isEmpty)
    }

    @Test("a sandboxed start of a StdioServerProcess leaves no current process")
    func sandboxedStartLeavesNoCurrentProcess() async throws {
        let stdio = try Self.makeSandboxedCat(registry: ProcessRegistry())

        _ = try? await stdio.respawn()

        #expect(stdio.currentPid == nil)
    }

    @Test("notAvailable is a non-retryable connect error")
    func notAvailableIsNonRetryable() {
        #expect(Self.processNotAvailable.isNonRetryable)
    }

    // MARK: - The builder

    @Test("a sandboxed builder with a server on an in-memory transport builds and has its noun")
    func sandboxedBuilderRegistersAnInMemoryServer() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedLoopbackMCPServer(
            over: .inMemory, name: Self.serverName)
        let builder = try await MultiTool.Builder(mode: .sandboxed, sandboxProbe: Self.sandboxedProcess)
            .withMCP(servers: [server])

        let registry = try withExtendedLifetime(scripted) { try builder.buildRegistry() }

        #expect(Self.nouns(of: registry) == [Self.serverName])
    }

    @Test("a sandboxed builder with a server over stdio throws notAvailable")
    func sandboxedBuilderRefusesAStdioServer() async throws {
        let error = try await Self.sandboxedStdioRefusal()

        #expect((error.kind, error.name) == Self.serverNotAvailable)
    }

    @Test("the sandboxed refusal of a server over stdio tells the host to connect it over HTTP")
    func sandboxedStdioRefusalGivesTheHTTPHint() async throws {
        let error = try await Self.sandboxedStdioRefusal()

        #expect(
            error.message.hasSuffix(MultiTool.RegistrySource.stdioServerRefusalHint),
            "message was: \(error.message)")
    }

    @Test("an open builder with a server over stdio builds and has its noun")
    func openBuilderRegistersAStdioServer() async throws {
        let registry = try await Self.withStdioServer { server in
            try await MultiTool.Builder(mode: .open, sandboxProbe: Self.openProcess)
                .withMCP(servers: [server])
                .buildRegistry()
        }

        #expect(Self.nouns(of: registry) == [Self.serverName])
    }
}
