import MCP
import MCPTestServer
import Testing

@testable import MultitoolTestSupport

/// Coverage for `ServerMode`, the `--mode` selector `mcp-test-server` parses
/// to decide which scripted tool set to register.
///
/// A port of
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/ServerModeTests.swift`,
/// plus one case for the `loopback` mode this package adds.
@Suite("ServerMode")
struct ServerModeTests {
    /// The `arguments[0]` every parse below carries — the binary name.
    private static let binaryName = "mcp-test-server"

    /// The spelling of the filesystem mode the source once accepted and the
    /// parse now rejects.
    private static let oldFilesystemSpelling = "filesystem"

    /// A mode name no case carries.
    private static let unknownModeName = "bogus"

    /// Connects a fresh client to `server` over an in-memory transport pair
    /// and returns every tool `tools/list` reports.
    ///
    /// - Parameter server: The scripted server to list tools from.
    /// - Returns: The registered tools, in `tools/list` order.
    /// - Throws: What the connect or the `tools/list` throws.
    private func registeredTools(on server: ScriptedServer) async throws -> [MCP.Tool] {
        let client = try await MCPTestSupport.connectedServer(
            to: server, over: .inMemory, clientName: "ServerModeTestClient")
        let (tools, _) = try await client.listTools()
        await client.disconnect()
        return tools
    }

    /// Connects a fresh client to `server` over an in-memory transport pair
    /// and returns the names of every tool `tools/list` reports.
    ///
    /// - Parameter server: The scripted server to list tools from.
    /// - Returns: The names of the registered tools, in `tools/list` order.
    /// - Throws: What the connect or the `tools/list` throws.
    private func registeredToolNames(on server: ScriptedServer) async throws -> [String] {
        try await registeredTools(on: server).map(\.name)
    }

    /// Whether `tools` is the tool set the dynamic scenario ends with: the
    /// re-schemad tool alone, under its new `inputSchema`.
    ///
    /// - Parameter tools: The tools `tools/list` reported.
    /// - Returns: `true` when every stage of the scenario ran.
    private static func isFinalDynamicToolset(_ tools: [MCP.Tool]) -> Bool {
        tools.map(\.name) == [ScriptedServer.dynamicToolsetReschemadToolName]
            && tools.first?.inputSchema != JSONSchemaBuilder.emptySchema
    }

    /// Parses `[binaryName] + rest`.
    ///
    /// - Parameter rest: The arguments after the binary name.
    /// - Returns: The parsed mode.
    private func parse(_ rest: [String]) -> ServerMode {
        ServerMode.parse(from: [Self.binaryName] + rest)
    }

    @Test("parse(from:) recognizes every case by its raw value")
    func parsesEveryCase() {
        for mode in ServerMode.allCases {
            #expect(parse([ServerMode.flagName, mode.rawValue]) == mode)
        }
    }

    @Test("parse(from:) rejects the old --mode filesystem spelling, falling back to .all")
    func rejectsOldFilesystemSpelling() {
        #expect(parse([ServerMode.flagName, Self.oldFilesystemSpelling]) == .all)
    }

    @Test("parse(from:) defaults to .all when no --mode flag is present")
    func defaultsToAllWhenFlagAbsent() {
        #expect(parse([]) == .all)
    }

    @Test("parse(from:) defaults to .all when --mode's value is unrecognized")
    func defaultsToAllWhenValueUnrecognized() {
        #expect(parse([ServerMode.flagName, Self.unknownModeName]) == .all)
    }

    @Test("parse(from:) defaults to .all when --mode is the last argument with no value")
    func defaultsToAllWhenFlagHasNoValue() {
        #expect(parse([ServerMode.flagName]) == .all)
    }

    @Test(".echo registers only the echo tool")
    func echoModeRegistersOnlyEchoTool() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.echo.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == [ScriptedServer.echoToolName])
    }

    @Test(".fileSystem registers only the filesystem tools")
    func filesystemModeRegistersOnlyFilesystemTools() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.fileSystem.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == ScriptedServer.filesystemToolNames)
    }

    @Test(".all registers both the echo tool and the filesystem tools")
    func allModeRegistersEverything() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.all.registerTools(on: server)

        #expect(
            try await registeredToolNames(on: server)
                == [ScriptedServer.echoToolName] + ScriptedServer.filesystemToolNames)
    }

    @Test(".eliciting registers only the elicit-on-command tool, under ServerMode.elicitOnCommandToolName")
    func elicitingModeRegistersOnlyElicitOnCommandTool() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.eliciting.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == [ServerMode.elicitOnCommandToolName])
    }

    @Test(".catalog registers only the catalog showcase tool")
    func catalogModeRegistersOnlyShowcaseTool() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.catalog.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == [ScriptedServer.catalogShowcaseToolName])
    }

    /// The stage clock stays closed, thus no stage can run before the list:
    /// the list reads the tool set of the registration alone.
    @Test(".dynamic registers the initial re-schemad tool up front")
    func dynamicModeRegistersInitialTool() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.dynamic.registerTools(on: server, stageClock: GatedClock())

        #expect(
            try await registeredToolNames(on: server) == [ScriptedServer.dynamicToolsetReschemadToolName])
    }

    @Test(".dynamic runs each stage after one stage delay on its stage clock")
    func dynamicModeRunsItsStagesOnTheStageClock() async throws {
        let server = ScriptedServer(name: "mode-test")
        let stageClock = GatedClock()
        await ServerMode.dynamic.registerTools(on: server, stageClock: stageClock)

        stageClock.open()

        try await TestPoll.waitUntil("every stage of the dynamic scenario ran") {
            ((try? await registeredTools(on: server)).map(Self.isFinalDynamicToolset)) ?? false
        }
        #expect(
            stageClock.recordedSleeps
                == Array(
                    repeating: ScriptedServer.dynamicToolsetStageDelay,
                    count: ScriptedServer.dynamicToolsetStageCount))
    }

    @Test(".longRunning registers only the slow-build tool, under ServerMode.slowBuildToolName")
    func longRunningModeRegistersOnlySlowBuildTool() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.longRunning.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == [ServerMode.slowBuildToolName])
    }

    @Test(".loopback registers echo, elicitEcho and elicitURL, by those names")
    func loopbackModeRegistersTheThreeLoopbackTools() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.loopback.registerTools(on: server)

        #expect(try await registeredToolNames(on: server) == ScriptedServer.loopbackToolNames)
        #expect(ScriptedServer.loopbackToolNames == ["echo", "elicitEcho", "elicitURL"])
    }

    @Test(".stall registers no tool and answers no request; each other mode answers")
    func stallModeRegistersNothingAndAnswersNothing() async throws {
        let server = ScriptedServer(name: "mode-test")
        await ServerMode.stall.registerTools(on: server)

        #expect(try await registeredToolNames(on: server).isEmpty)
        #expect(ServerMode.allCases.filter { !$0.answersRequests } == [.stall])
    }
}
