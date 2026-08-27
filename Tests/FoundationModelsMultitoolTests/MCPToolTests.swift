import Foundation
import FoundationModels
import FoundationModelsRouter
import MCP
import MCPTestServer
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Coverage for ``MCPTool``, the plain `FoundationModels.Tool` verb over one
/// tool of one ``MCPServer``.
///
/// Ported from
/// `../FoundationModelsMCP/Tests/FoundationModelsMCPTests/MCPToolTests.swift`.
/// The sibling drove each case against a `MockClient` behind the
/// `MCPToolCalling` seam; here the server is the one seam, so every case runs
/// against a `ScriptedServer` connected to a real `MCPServer`. The cases of
/// the source that are not here, and why:
///
/// - the `waiting(for:)` cases — the soft deadline is gone; the engine of
///   Router is the clock of a call made under a context.
/// - the `operationRoute` cases — the Operations-shaped route is gone; a
///   progress notification reaches the ambient `ToolContext`.
///
/// `propagatesThrownTransportError` of the source stands here as the
/// JSON-RPC error a server answers, which the verb rethrows unchanged. The
/// metadata the sibling read off `MCPTool` — `title`, the raw `inputSchema` —
/// stands on `MCPCatalogEntry` here, so that case reads `tool.entry`.
///
/// Two cases are new: the illegal verb name, which `buildRegistry()` refuses
/// with `ToolAPIRendererError`, and the portability case, which calls the
/// verb with no ambient `ToolContext` against a tool that sends progress.
@Suite("MCPToolTests")
struct MCPToolTests {

    // MARK: - Shared test constants

    /// The name every server of this suite is constructed with.
    private static let serverName = "mcp-tool-test-server"

    /// The text the echo cases send and expect back.
    private static let echoText = "hello world"

    /// The name of the tool that records the arguments it receives.
    private static let recordingToolName = "record"

    /// The nested-argument keys of the round-trip case.
    private static let addressArgument = "address"

    /// The inner key of the nested object of the round-trip case.
    private static let cityArgument = "city"

    /// The city of the nested object of the round-trip case.
    private static let cityText = "Springfield"

    /// The array-valued key of the round-trip case.
    private static let tagsArgument = "tags"

    /// The elements of the array of the round-trip case.
    private static let tagTexts = ["a", "b"]

    /// The name of the tool that answers an `isError` result.
    private static let failingToolName = "fails"

    /// The text the failing tool answers.
    private static let failingToolText = "boom"

    /// The name of the tool that answers `structuredContent` beside text.
    private static let structuredToolName = "structured"

    /// The text the structured tool answers.
    private static let structuredToolText = "done"

    /// The key of the structured answer.
    private static let answerKey = "answer"

    /// The value of the structured answer.
    private static let answerValue = 42

    /// The name of the tool whose handler throws.
    private static let throwingToolName = "throws"

    /// The message the throwing tool throws.
    private static let throwingToolMessage = "the handler refused"

    /// A verb name the TypeScript surface cannot carry — the hyphen breaks
    /// `ToolAPIRenderer.isLegalTSIdentifier`.
    private static let illegalToolName = "create-issue"

    /// The name of the progress-reporting tool of the portability case.
    private static let progressToolName = "slow"

    /// How many progress notifications the progress tool sends.
    private static let progressSteps = 3

    /// How long the progress tool waits between notifications.
    private static let progressStepDelay = Duration.milliseconds(5)

    /// A render budget far under the echoed text of the budget cases.
    private static let tightBudgetCharacters = 16

    /// How many characters the oversized echo of the budget cases carries.
    private static let oversizedTextCount = 64

    /// The one character the oversized echo repeats.
    private static let oversizedTextUnit = "x"

    /// The head of the elision marker `ToolContentRenderer` inserts.
    private static let elisionMarkerPrefix = "[elided"

    /// The `Error:` paragraph the renderer prepends to an `isError` result.
    private static let renderedErrorHeading = "Error:"

    /// The description the metadata case declares.
    private static let searchDescription = "Searches things"

    /// The title the metadata case declares.
    private static let searchTitle = "Search Tool"

    /// The name the metadata case declares.
    private static let searchToolName = "search"

    /// The empty object schema every argument-free tool of this suite declares.
    private static let anyObjectSchema = JSONSchemaBuilder.emptySchema

    // MARK: - Helpers

    /// The arguments every `tools/call` of one scripted tool carried, in
    /// call order — what the round-trip cases read back.
    private final class ArgumentRecorder: Sendable {
        /// Each argument map received, in call order.
        private let storage = Mutex<[[String: Value]?]>([])

        /// Each argument map received, in call order.
        var received: [[String: Value]?] {
            storage.withLock { $0 }
        }

        /// Appends one received argument map.
        ///
        /// - Parameter arguments: The arguments of one call.
        func record(_ arguments: [String: Value]?) {
            storage.withLock { $0.append(arguments) }
        }
    }

    /// A scripted tool that records the arguments of every call into
    /// `recorder` and answers an empty result.
    ///
    /// - Parameters:
    ///   - inputSchema: The `inputSchema` the tool declares.
    ///   - recorder: Where each call's arguments go.
    /// - Returns: The scripted tool.
    private static func recordingTool(
        inputSchema: Value, into recorder: ArgumentRecorder
    ) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: recordingToolName, description: "Records its arguments.",
                inputSchema: inputSchema)
        ) { params in
            recorder.record(params.arguments)
            return CallTool.Result(content: [])
        }
    }

    /// A scripted tool that answers `result` at once.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - result: The result the handler answers.
    /// - Returns: The scripted tool.
    private static func answeringTool(named name: String, with result: CallTool.Result) -> ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(name: name, description: "Answers at once.", inputSchema: anyObjectSchema)
        ) { _ in result }
    }

    /// A scripted tool that answers an `isError` result at once.
    private static var failingTool: ScriptedTool {
        answeringTool(
            named: failingToolName,
            with: CallTool.Result(
                content: [.text(text: failingToolText, annotations: nil, _meta: nil)],
                isError: true))
    }

    /// A scripted tool that answers text beside `structuredContent`.
    private static var structuredTool: ScriptedTool {
        answeringTool(
            named: structuredToolName,
            with: CallTool.Result(
                content: [.text(text: structuredToolText, annotations: nil, _meta: nil)],
                structuredContent: .object([answerKey: .int(answerValue)])))
    }

    /// A scripted tool whose handler throws, so the server answers a
    /// JSON-RPC error.
    private static var throwingTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: throwingToolName, description: "Throws.", inputSchema: anyObjectSchema)
        ) { _ in
            throw MCPError.internalError(throwingToolMessage)
        }
    }

    /// A scripted server that serves `tools`, connected to a fresh
    /// `MCPServer` named ``serverName`` over the in-memory transport.
    ///
    /// - Parameters:
    ///   - tools: The tools to register before the connect.
    ///   - renderBudget: The render budget of the server.
    /// - Returns: The scripted server, which the test keeps alive, and the
    ///   connected server.
    /// - Throws: What the connect throws.
    private static func connected(
        serving tools: [ScriptedTool], renderBudget: RenderBudget = .default
    ) async throws -> (scripted: ScriptedServer, server: MCPServer) {
        try await MCPTestSupport.connectedMCPServer(
            serving: tools, name: serverName, renderBudget: renderBudget)
    }

    /// The verb of `server` for the tool named `name`.
    ///
    /// - Parameters:
    ///   - name: The name of the discovered tool.
    ///   - server: The connected server.
    /// - Returns: The verb.
    /// - Throws: When `server` discovered no tool named `name`.
    private static func tool(named name: String, on server: MCPServer) async throws -> MCPTool {
        let entry = try #require(await server.tool(named: name))
        return MCPTool(entry: entry, server: server)
    }

    /// The sorted-key JSON of `schema` — the one comparable form of a
    /// `GenerationSchema`, whose plain encoding orders its keys at random.
    ///
    /// - Parameter schema: The schema to encode.
    /// - Returns: The JSON text.
    /// - Throws: What `JSONEncoder.encode(_:)` throws.
    private static func canonicalJSON(of schema: GenerationSchema) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(schema), as: UTF8.self)
    }

    /// The generated arguments of one echo call.
    private static var echoArguments: GeneratedContent {
        GeneratedContent(properties: [ScriptedServer.echoTextArgument: echoText])
    }

    /// The generated arguments of one echo call of an oversized text.
    private static var oversizedEchoArguments: GeneratedContent {
        GeneratedContent(properties: [
            ScriptedServer.echoTextArgument: String(
                repeating: oversizedTextUnit, count: oversizedTextCount)
        ])
    }

    // MARK: - Forwarding: the exact name and the encoded arguments reach the server

    @Test("call(arguments:) forwards the exact tool name and encoded arguments to the server")
    func forwardsNameAndArgumentsExactly() async throws {
        let recorder = ArgumentRecorder()
        let (scripted, server) = try await Self.connected(
            serving: [Self.recordingTool(inputSchema: Self.anyObjectSchema, into: recorder)])
        let tool = try await Self.tool(named: Self.recordingToolName, on: server)

        _ = try await tool.call(arguments: Self.echoArguments)

        #expect(recorder.received == [[ScriptedServer.echoTextArgument: .string(Self.echoText)]])
        withExtendedLifetime(scripted) {}
    }

    @Test("call(arguments:) forwards nested object and array arguments as the same [String: Value]")
    func forwardsNestedArgumentsExactly() async throws {
        let recorder = ArgumentRecorder()
        let (scripted, server) = try await Self.connected(
            serving: [Self.recordingTool(inputSchema: Self.anyObjectSchema, into: recorder)])
        let tool = try await Self.tool(named: Self.recordingToolName, on: server)
        let inner = GeneratedContent(properties: [Self.cityArgument: Self.cityText])
        let arguments = GeneratedContent(
            properties: [
                Self.addressArgument: inner,
                Self.tagsArgument: Self.tagTexts,
            ] as KeyValuePairs<String, any ConvertibleToGeneratedContent>)

        _ = try await tool.call(arguments: arguments)

        #expect(
            recorder.received == [
                [
                    Self.addressArgument: .object([Self.cityArgument: .string(Self.cityText)]),
                    Self.tagsArgument: .array(Self.tagTexts.map(Value.string)),
                ]
            ])
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Rendering: success, isError, structuredContent

    @Test("call(arguments:) renders a successful result for the model")
    func rendersSuccessResult() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        let tool = try await Self.tool(named: ScriptedServer.echoToolName, on: server)

        let output = try await tool.call(arguments: Self.echoArguments)

        #expect(output == Self.echoText)
        withExtendedLifetime(scripted) {}
    }

    @Test("call(arguments:) renders an isError result as model-consumable text, never throwing")
    func rendersIsErrorResultWithoutThrowing() async throws {
        let (scripted, server) = try await Self.connected(serving: [Self.failingTool])
        let tool = try await Self.tool(named: Self.failingToolName, on: server)

        let output = try await tool.call(arguments: GeneratedContent(properties: [:]))

        #expect(output.contains(Self.renderedErrorHeading))
        #expect(output.contains(Self.failingToolText))
        withExtendedLifetime(scripted) {}
    }

    @Test("call(arguments:) renders structuredContent alongside content")
    func rendersStructuredContentAlongsideContent() async throws {
        let (scripted, server) = try await Self.connected(serving: [Self.structuredTool])
        let tool = try await Self.tool(named: Self.structuredToolName, on: server)

        let output = try await tool.call(arguments: GeneratedContent(properties: [:]))

        #expect(output.contains(Self.structuredToolText))
        #expect(output.contains(String(Self.answerValue)))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - The render budget

    @Test("the rendered output is bounded by the server's render budget")
    func rendersUnderTheServersBudget() async throws {
        let (scripted, server) = try await Self.connected(
            serving: [ScriptedServer.echoTool()],
            renderBudget: .limited(characters: Self.tightBudgetCharacters))
        let tool = try await Self.tool(named: ScriptedServer.echoToolName, on: server)

        let output = try await tool.call(arguments: Self.oversizedEchoArguments)

        #expect(output.contains(Self.elisionMarkerPrefix), "output was: \(output)")
        withExtendedLifetime(scripted) {}
    }

    @Test("rendering(withBudget:) overrides the server's render budget for this tool alone")
    func renderingWithBudgetOverridesTheServersBudget() async throws {
        let (scripted, server) = try await Self.connected(
            serving: [ScriptedServer.echoTool()],
            renderBudget: .limited(characters: Self.tightBudgetCharacters))
        let tool = try await Self.tool(named: ScriptedServer.echoToolName, on: server)
            .rendering(withBudget: .unlimited)

        let output = try await tool.call(arguments: Self.oversizedEchoArguments)

        #expect(output == String(repeating: Self.oversizedTextUnit, count: Self.oversizedTextCount))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A thrown server error propagates

    @Test("call(arguments:) rethrows the JSON-RPC error the server answered, unchanged")
    func propagatesServerError() async throws {
        let (scripted, server) = try await Self.connected(serving: [Self.throwingTool])
        let tool = try await Self.tool(named: Self.throwingToolName, on: server)

        await #expect(throws: MCPError.self) {
            _ = try await tool.call(arguments: GeneratedContent(properties: [:]))
        }
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Metadata sourced verbatim from the catalog entry

    @Test("name and description are the server's, and title and the raw inputSchema stand on the entry")
    func exposesMetadataFromCatalogEntry() async throws {
        let (scripted, server) = try await Self.connected(
            serving: [
                Self.answeringTool(
                    named: Self.searchToolName, with: CallTool.Result(content: []))
            ])
        let discovered = try #require(await server.tool(named: Self.searchToolName))
        let sourceTool = MCP.Tool(
            name: Self.searchToolName, title: Self.searchTitle, description: Self.searchDescription,
            inputSchema: Self.anyObjectSchema)
        let entry = try MCPCatalogEntry(tool: sourceTool)
        let tool = MCPTool(entry: entry, server: server)

        #expect(tool.name == Self.searchToolName)
        #expect(tool.description == Self.searchDescription)
        #expect(tool.entry.title == Self.searchTitle)
        #expect(tool.entry.inputSchema == Self.anyObjectSchema)
        #expect(discovered.name == tool.name)
        withExtendedLifetime(scripted) {}
    }

    @Test("description falls back to an empty string when the server declared none")
    func descriptionFallsBackToEmptyStringWhenAbsent() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        let sourceTool = MCP.Tool(
            name: Self.searchToolName, description: nil, inputSchema: Self.anyObjectSchema)
        let entry = try MCPCatalogEntry(tool: sourceTool)

        let tool = MCPTool(entry: entry, server: server)

        #expect(tool.description.isEmpty)
        withExtendedLifetime(scripted) {}
    }

    @Test("includesSchemaInInstructions is always true")
    func includesSchemaInInstructionsIsAlwaysTrue() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])

        let tool = try await Self.tool(named: ScriptedServer.echoToolName, on: server)

        #expect(tool.includesSchemaInInstructions)
        withExtendedLifetime(scripted) {}
    }

    @Test("parameters is the converted schema of the catalog entry")
    func parametersIsTheConvertedSchemaOfTheEntry() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])
        let entry = try #require(await server.tool(named: ScriptedServer.echoToolName))

        let tool = MCPTool(entry: entry, server: server)

        // `GenerationSchema` has no public equality; the sorted-key JSON it
        // encodes to is the strongest comparison available, and it is what
        // `ToolAPIRenderer` reads.
        #expect(try Self.canonicalJSON(of: tool.parameters) == Self.canonicalJSON(of: entry.parameters))
        withExtendedLifetime(scripted) {}
    }

    // MARK: - A plain Tool, and portable

    @Test("MCPTool does not conform to BackgroundTool")
    func doesNotConformToBackgroundTool() async throws {
        let (scripted, server) = try await Self.connected(serving: [ScriptedServer.echoTool()])

        let tool = try await Self.tool(named: ScriptedServer.echoToolName, on: server)

        #expect(!((tool as Any) is any BackgroundTool))
        withExtendedLifetime(scripted) {}
    }

    /// The bare-session path: no `ToolContext` is bound, the server sends
    /// progress during the call, and the call still returns the rendered
    /// result — a progress notification with no context posts nothing.
    ///
    /// The progress tool is registered after the connect, so the discovery
    /// of the server never saw it; the verb is built over an entry of the
    /// same name and schema, and the call reaches the tool by name.
    @Test("with no ToolContext bound, call(arguments:) returns the rendered result while the server sends progress")
    func callsWithNoAmbientContext() async throws {
        let (scripted, server) = try await Self.connected(serving: [])
        await scripted.addProgressReportingTool(
            named: Self.progressToolName, totalSteps: Self.progressSteps,
            stepDelay: Self.progressStepDelay)
        let entry = try MCPCatalogEntry(
            tool: MCP.Tool(
                name: Self.progressToolName, description: nil, inputSchema: Self.anyObjectSchema))
        let tool = MCPTool(entry: entry, server: server)

        let output = try await tool.call(arguments: GeneratedContent(properties: [:]))

        #expect(ToolContext.current == nil)
        #expect(output == ScriptedServer.progressToolCompletionText)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Verb legality

    /// The rule is `ToolAPIRenderer.isLegalTSIdentifier`, and the renderer
    /// throws at `buildRegistry()`: the verb itself constructs, and the
    /// failure is the loud one at build, never a rewrite of the name.
    @Test("a tool named create-issue fails at buildRegistry() with ToolAPIRendererError, not at dispatch")
    func illegalNameFailsAtBuildRegistry() async throws {
        let (scripted, server) = try await Self.connected(
            serving: [ScriptedServer.echoTool(named: Self.illegalToolName)])
        let tool = try await Self.tool(named: Self.illegalToolName, on: server)

        #expect(tool.name == Self.illegalToolName)
        #expect {
            try MultiTool.Builder()
                .addTool(tool)
                .buildRegistry()
        } throws: { error in
            error is ToolAPIRendererError
        }
        withExtendedLifetime(scripted) {}
    }
}
