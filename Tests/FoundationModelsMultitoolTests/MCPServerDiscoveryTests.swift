import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the discovery half of `MCPServer`: paginated `tools/list`
/// completeness, the `connecting` / `ready` / `faulted` state machine around
/// a connect, `mcpTools()` and `catalog` before and after readiness, and
/// `ServerIdentity` stability across a reconnect.
///
/// A port of `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/MCPServerDiscoveryTests.swift`,
/// plus the two `MCPServer.catalog` cases of `CatalogTypeTests.swift` there.
/// Every case drives a real `MCP.Client` against a `ScriptedServer` over an
/// in-memory pair, because only a real pair drives the `tools/list`
/// pagination and the `initialize` handshake.
///
/// **One case of the source is not here.**
/// `foundationModelsToolsVendsDiscoveredTools` asserts on `MCPTool`, the
/// call-path adapter this package does not port.
@Suite("MCPServerDiscoveryTests")
struct MCPServerDiscoveryTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with, and so the
    /// identity a successful connect establishes.
    private static let serverName = "discovery-test-server"

    /// How many tools the pagination case registers — more than two pages
    /// of ``pageSize``, so the last page is partial.
    private static let paginatedToolCount = 5

    /// The `tools/list` page size of the pagination case.
    private static let pageSize = 2

    /// The epoch of the first snapshot a connect emits.
    private static let firstEpoch = 1

    /// How many leading connect attempts the flaky transport fails.
    private static let oneFailingAttempt = 1

    /// An `inputSchema` whose `$ref` names no `$defs` entry —
    /// `SchemaConverter.emit(_:)` throws for it, so `MCPCatalogEntry.init(tool:)`
    /// throws mid-discovery, after the handshake already succeeded.
    private static let danglingReferenceSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "value": .object(["$ref": .string("#/$defs/Missing")])
        ]),
        "required": .array([.string("value")]),
    ])

    // MARK: - Helpers

    /// A `ScriptedServer` serving one echo tool per name in `names`.
    ///
    /// - Parameters:
    ///   - names: The names of the echo tools to register.
    ///   - toolsPageSize: The `tools/list` page size. Defaults to one page.
    /// - Returns: The scripted server, not yet started.
    private static func scriptedServer(
        echoing names: [String], toolsPageSize: Int? = nil
    ) async -> ScriptedServer {
        let scripted = ScriptedServer(toolsPageSize: toolsPageSize)
        for name in names {
            await scripted.addTool(ScriptedServer.echoTool(named: name))
        }
        return scripted
    }

    // MARK: - Paginated discovery completeness

    @Test func discoversAllToolsAcrossPagination() async throws {
        let expectedNames = (0..<Self.paginatedToolCount).map { "tool-\($0)" }
        let scripted = await Self.scriptedServer(echoing: expectedNames, toolsPageSize: Self.pageSize)
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)

        let tools = try await server.mcpTools()

        #expect(tools.count == Self.paginatedToolCount)
        #expect(tools.map(\.name) == expectedNames)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Readiness state machine

    @Test func stateTransitionsToReadyOnSuccess() async throws {
        let scripted = ScriptedServer()
        await scripted.addEchoTool()
        let transport = try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory)
        let server = MCPServer(name: Self.serverName)
        #expect(await server.state == .connecting)

        try await server.connect(via: transport)

        #expect(await server.state == .ready)
        withExtendedLifetime(scripted) {}
    }

    @Test func stateBecomesFaultedOnConnectFailure() async throws {
        let (clientTransport, _) = await InMemoryTransport.createConnectedPair()
        let flaky = FlakyConnectTransport(
            wrapping: clientTransport, failingConnectAttempts: Self.oneFailingAttempt)
        let server = MCPServer(name: Self.serverName)

        await #expect(throws: (any Error).self) {
            try await server.connect(via: flaky)
        }

        guard case .faulted = await server.state else {
            Issue.record("expected .faulted state after a scripted connect failure")
            return
        }
    }

    @Test func mcpToolsThrowsBeforeReady() async throws {
        let server = MCPServer(name: Self.serverName)

        await #expect(throws: MCPServerError.self) {
            _ = try await server.mcpTools()
        }
    }

    @Test func identityRemainsNilWhenDiscoveryFailsAfterSuccessfulHandshake() async throws {
        let scripted = ScriptedServer()
        await scripted.addTool(
            ScriptedTool(
                definition: MCP.Tool(
                    name: "malformed",
                    description: "A tool whose inputSchema references an undeclared $defs entry.",
                    inputSchema: Self.danglingReferenceSchema
                ),
                handler: { _ in CallTool.Result(content: []) }
            )
        )
        let transport = try await MCPTestSupport.clientTransport(serving: scripted, over: .inMemory)
        let server = MCPServer(name: Self.serverName)

        await #expect(throws: (any Error).self) {
            try await server.connect(via: transport)
        }

        guard case .faulted = await server.state else {
            Issue.record("expected .faulted state after a discovery-phase failure")
            return
        }
        #expect(await server.identity == nil)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The catalog a host reads

    @Test func catalogReflectsDiscoveredToolsAfterConnect() async throws {
        let scripted = await Self.scriptedServer(echoing: ["echo"])
        let server = try await MCPTestSupport.connectedMCPServer(
            to: scripted, over: .inMemory, name: Self.serverName)

        let catalog = try await server.catalog

        #expect(catalog.tools.map(\.name) == ["echo"])
        #expect(catalog.state == .ready)
        #expect(catalog.epoch == Self.firstEpoch)
        #expect(catalog.identity == ServerIdentity(name: Self.serverName))
        withExtendedLifetime(scripted) {}
    }

    @Test func catalogThrowsBeforeReady() async throws {
        let server = MCPServer(name: Self.serverName)

        await #expect(throws: MCPServerError.self) {
            _ = try await server.catalog
        }
    }

    // MARK: - ServerIdentity stability

    /// The identity is the name the host constructed the server with, so a
    /// reconnect to a server that reports another name moves nothing.
    @Test func identityStableAcrossReconnectToARenamedServer() async throws {
        let first = ScriptedServer(name: "primary-server")
        await first.addEchoTool()
        let server = try await MCPTestSupport.connectedMCPServer(
            to: first, over: .inMemory, name: Self.serverName)
        let firstIdentity = await server.identity

        await server.disconnect()

        let second = ScriptedServer(name: "renamed-server")
        await second.addEchoTool()
        let transport = try await MCPTestSupport.clientTransport(serving: second, over: .inMemory)
        try await server.connect(via: transport)
        let secondIdentity = await server.identity

        #expect(firstIdentity == ServerIdentity(name: Self.serverName))
        #expect(firstIdentity == secondIdentity)
        withExtendedLifetime((first, second)) {}
    }
}
