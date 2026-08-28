import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `MCPCapability` and for `MultiTool.Builder.withMCP(servers:)` —
/// eventplan.md § "The capability contract": *"The modules are opt-in:
/// `withShell()`, `withFiles()`, and `withMCP(servers:)`."*
///
/// Three sentences of eventplan.md carry this suite:
///
/// 1. § "Consolidation of the siblings": "Each connected server registers as
///    its own top-level group: `tools.github.createIssue`, never
///    `tools.mcp.github.createIssue`. The model must not see the transport."
/// 2. § "Registration of capabilities: noun/verb": "An MCP server with the
///    name `files`, against the files capability, fails loudly at
///    `buildRegistry()`."
/// 3. § "Servers connect before `buildRegistry()`." — `withMCP(servers:)`
///    awaits readiness, and it does not connect.
///
/// Each case that reaches the server runs over both transports of
/// ``MCPTransportKind``, thus the model reads one surface whether the server
/// stands in memory or behind the in-process HTTP loopback.
///
/// The suite is `.serialized` for the reason `LoopbackHTTPServerTests` states:
/// a connect over `.http` holds a live `HTTPClientTransport` SSE stream open
/// through `URLSession` for the whole test, and several such streams at once
/// tip the shared cooperative pool past the threshold where a server message
/// stalls. One stream at a time stays under it. Every test still runs on
/// every `swift test`.
@Suite("MCPCapabilityTests", .serialized)
struct MCPCapabilityTests {

    /// Owns the temporary directories this test makes, so they go away when
    /// the test ends and they do not collect in `$TMPDIR`.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test, so a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "mcpcapability-tests"

    /// The name every server of this suite is constructed with, and so the
    /// noun its verbs render under.
    private static let serverName = "loopback"

    /// The name of the server the duplicate-noun case constructs: the noun
    /// the files capability owns.
    private static let filesNoun = "files"

    /// The two transports every case that reaches the server runs over.
    private static let transports: [MCPTransportKind] = [.inMemory, .http]

    /// The text the echo case sends and expects back.
    private static let echoText = "through the capability"

    /// The first segment the sibling design gave every MCP path, with its
    /// separator. eventplan.md removes it: no path opens with it.
    private static let transportGroupPrefix = "mcp."

    /// The rendered call path of each loopback verb, built from the noun and
    /// the tool names the test server publishes, so the noun and the verbs
    /// have one home here.
    private static let loopbackPaths = ScriptedServer.loopbackToolNames.map { "\(serverName).\($0)" }

    /// The rendered call path of the echo verb.
    private static let echoPath = "\(serverName).\(ScriptedServer.echoToolName)"

    /// The plain-language goal the discovery test searches for.
    private static let loopbackTask = "echo text back through the loopback server"

    /// The wall-clock ceiling of the sandbox the dry run of an example runs in.
    private static let dryRunTimeLimit: TimeInterval = 5.0

    /// What the scripted selection tier answers: every loopback verb, by its
    /// rendered path. Built from ``loopbackPaths`` so a verb added or taken
    /// away moves the reply with it.
    private static var selectionReply: String {
        let ids = loopbackPaths.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"ids\":[\(ids)]}"
    }

    // MARK: - The ground of one test

    /// A fresh scripted server that serves the three loopback tools, beside a
    /// server named ``serverName`` connected against it over `kind`.
    ///
    /// - Parameter kind: The transport to connect over.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        over kind: MCPTransportKind
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedLoopbackMCPServer(over: kind, name: serverName)
    }

    /// A registry holding the MCP capability of `server` and nothing else.
    ///
    /// - Parameter server: The connected server.
    /// - Returns: The registry.
    /// - Throws: What `withMCP(servers:)` or `buildRegistry()` throws.
    private static func makeRegistry(over server: MCPServer) async throws -> MultiTool.Registry {
        try await MultiTool.Builder()
            .withMCP(servers: [server])
            .buildRegistry()
    }

    /// Runs one `runCode` snippet over `registry` and decodes the string it
    /// returned.
    ///
    /// - Parameters:
    ///   - code: The snippet to run.
    ///   - registry: The catalog the snippet's `tools.*` calls dispatch into.
    /// - Returns: The decoded string.
    /// - Throws: What `MultiTool.call(arguments:)` or the decode throws.
    private static func stringResult(
        of code: String, over registry: MultiTool.Registry
    ) async throws -> String {
        let multiTool = MultiTool(registry: registry)
        let output = try await multiTool.call(arguments: RunCodeArguments(code: code))
        return try JSONDecoder().decode(String.self, from: Data(output.utf8))
    }

    /// A `searchTools` over `surface` whose selection tier answers every
    /// loopback verb.
    ///
    /// - Parameter surface: The rendered surface to search.
    /// - Returns: The discovery tool.
    private static func makeSearchTools(over surface: APISurface) -> SearchToolsTool {
        let selection = RootSessionRespondCalledDirectlySession(forkResponses: [selectionReply])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _, _ in selection }, capacityCharacterLimit: .max)
        )
        return SearchToolsTool(searcher: searcher, limit: surface.entries.count)
    }

    // MARK: - The noun and its verbs

    /// eventplan.md § "Registration of capabilities: noun/verb": the server is
    /// the noun, and each tool of its catalog is a verb.
    @Test("the capability owns the server name as its noun and holds one verb for each catalog entry")
    func theCapabilityOwnsTheServerNameAndHoldsOneVerbPerTool() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)

        let capability = try await MCPCapability(server: server)

        #expect(capability.noun == Self.serverName)
        #expect(capability.tools.map { $0.name } == ScriptedServer.loopbackToolNames)
        #expect(capability.tools.allSatisfy { $0 is MCPTool })
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The rendered surface

    /// eventplan.md § "Consolidation of the siblings": each server is its own
    /// top-level group, and no `tools.mcp` group exists.
    @Test("withMCP renders tools.<serverName>.<toolName> for each server tool, and no tools.mcp group", arguments: transports)
    func withMCPRendersOneGroupPerServer(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        defer { Task { await server.disconnect() } }

        let registry = try await Self.makeRegistry(over: server)

        let paths = registry.surface.entries.map(\.path)
        #expect(paths == Self.loopbackPaths)
        #expect(registry.surface.entries.allSatisfy { $0.group == Self.serverName })
        #expect(!paths.contains { $0.hasPrefix(Self.transportGroupPrefix) })
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A snippet reaches the server

    @Test("a snippet that awaits tools.<serverName>.echo reaches the loopback server and returns the rendered result", arguments: transports)
    func anEchoSnippetReachesTheServer(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        defer { Task { await server.disconnect() } }
        let registry = try await Self.makeRegistry(over: server)

        let result = try await Self.stringResult(
            of: "return await tools.\(Self.echoPath)({ \(ScriptedServer.echoTextArgument): \"\(Self.echoText)\" });",
            over: registry)

        #expect(result == Self.echoText)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Discovery

    /// eventplan.md § "Registration of capabilities: noun/verb": "The path, the
    /// `findAPIs` result, the `help()` entry ... all come from the one pair."
    /// `findAPIs` ships as `searchTools`, and it ranks a server tool through
    /// the same selection tier as a built-in verb. Each result carries the
    /// example the generic sample generator wrote for the converted schema,
    /// and that example runs: against typed mocks for every verb, and against
    /// the server for the echo verb.
    @Test("searchTools finds each server verb with a sample snippet that runs", arguments: transports)
    func searchToolsFindsEachServerVerbWithARunnableExample(kind: MCPTransportKind) async throws {
        let (scripted, server) = try await Self.connected(over: kind)
        defer { Task { await server.disconnect() } }
        let registry = try await Self.makeRegistry(over: server)
        let surface = registry.surface
        let searchTools = Self.makeSearchTools(over: surface)

        let feedback = try await searchTools.call(
            arguments: SearchToolsArguments(task: Self.loopbackTask))

        for path in Self.loopbackPaths {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(feedback.contains(entry.block), "feedback was: \(feedback)")
            #expect(feedback.contains("Example: \(entry.qualifiedExample)"))
            #expect(entry.qualifiedExample.hasPrefix("await tools.\(path)("))
            let dryRunFailure = TypedMockDryRun.apiUsageFailure(
                in: entry.qualifiedExample,
                against: [entry],
                using: JSCInterpreter(timeLimit: Self.dryRunTimeLimit))
            #expect(dryRunFailure == nil, "the example of \(path) failed its dry run: \(dryRunFailure ?? "")")
        }

        let echo = try #require(surface.entries.first { $0.path == Self.echoPath })
        let echoed = try await Self.stringResult(of: "return \(echo.qualifiedExample);", over: registry)
        #expect(echoed == ScriptedServer.echoTextArgument)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The duplicate noun

    /// eventplan.md § "Registration of capabilities: noun/verb": "An MCP
    /// server with the name `files`, against the files capability, fails
    /// loudly at `buildRegistry()`." `withCapability(_:)` claims the noun, so
    /// no new code decides this; the test pins it for the real server.
    @Test("a server named files beside withFiles(root:) fails at buildRegistry() with duplicateNoun")
    func aServerNamedFilesBesideTheFilesCapabilityThrowsAtBuild() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedLoopbackMCPServer(
            over: .inMemory, name: Self.filesNoun)
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let builder = try await MultiTool.Builder()
            .withFiles(root: root)
            .withMCP(servers: [server])

        #expect {
            try builder.buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == Self.filesNoun
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Readiness

    /// `withMCP(servers:)` awaits readiness, and it does not connect. A server
    /// that can no longer reach `.ready` — here, one the host disconnected —
    /// makes the builder throw rather than register an empty group.
    @Test("a server that never reaches .ready makes withMCP throw MCPServerError.notReady")
    func aServerThatNeverReachesReadyThrowsNotReady() async throws {
        let (scripted, server) = try await Self.connected(over: .inMemory)
        await server.disconnect()

        await #expect {
            try await MultiTool.Builder().withMCP(servers: [server])
        } throws: { error in
            guard case .notReady = error as? MCPServerError else { return false }
            return true
        }
        withExtendedLifetime(scripted) {}
    }
}
