// `MCPToolContentTests` — an MCP tool result keeps its image blocks for the
// host.
//
// The request (TestudoApp ^v30ggjj): `MCPTool.call(arguments:)` gives the
// model only text, and the renderer changes an image block to
// `[image: <mimeType>]`. Thus the image data was lost before the host got the
// result. Now the verb also posts the ordered content blocks of the result to
// the host, as one display chunk through the ambient `ToolContext`. The host
// reads the chunk with `MCPToolContent(display:)`. The text that the model
// reads does not change.
//
// Each test mounts the verb on the context of a stub run, with a
// `RecordingEventSink`, and reads the display events of that sink. No test
// uses a clock: a synchronous call posts its display events before it
// returns.

import FoundationModels
import FoundationModelsExtras
import MCP
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("MCPToolContentTests", .ownsTemporaryDirectories)
struct MCPToolContentTests {

    /// The name of the server of each test.
    private static let serverName = "content"

    /// The name of the tool that answers an image beside text.
    private static let imageToolName = "snapshot"

    /// The text that the image tool answers before its image.
    private static let captionText = "the screen"

    /// The base64 data of the image block.
    private static let imageData = "iVBORw0KGgo="

    /// The mime type of the image block.
    private static let imageMimeType = "image/png"

    /// The content blocks that the image tool answers, in order.
    private static let imageBlocks: [MCP.Tool.Content] = [
        .text(text: captionText, annotations: nil, _meta: nil),
        .image(data: imageData, mimeType: imageMimeType, annotations: nil, _meta: nil),
    ]

    /// The scripted tool that answers ``imageBlocks``.
    private static var imageTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: imageToolName, description: "Answers an image.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in CallTool.Result(content: imageBlocks) }
    }

    /// The content chunks that `sink` got, in order.
    ///
    /// - Parameter sink: the sink to read.
    /// - Returns: the content of each `.contentChunk` display event.
    private static func chunks(in sink: RecordingEventSink) async -> [ToolDisplayContent] {
        await sink.displayEvents.compactMap { event in
            guard case .contentChunk(let content) = event.kind else { return nil }
            return content
        }
    }

    @Test("a result with an image posts its blocks to the host, and the model text does not change")
    func imageResultPostsItsBlocks() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [Self.imageTool], name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await MCPTestSupport.tool(named: Self.imageToolName, on: server)
            try await withStubRun { run in
                let sink = RecordingEventSink()
                let output = try await run.context.mount(tool, as: .synchronous, postingTo: sink)
                    .call(arguments: GeneratedContent(properties: [:]))

                #expect(output == "\(Self.captionText)\n[image: \(Self.imageMimeType)]")
                let chunks = await Self.chunks(in: sink)
                #expect(chunks.count == 1)
                let content = try #require(chunks.first.flatMap(MCPToolContent.init(display:)))
                #expect(content == MCPToolContent(content: Self.imageBlocks, isError: false))
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a text-only result posts no display chunk")
    func textOnlyResultPostsNothing() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [ScriptedServer.echoTool()], name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let tool = try await MCPTestSupport.tool(named: ScriptedServer.echoToolName, on: server)
            try await withStubRun { run in
                let sink = RecordingEventSink()
                _ = try await run.context.mount(tool, as: .synchronous, postingTo: sink)
                    .call(arguments: GeneratedContent(properties: [ScriptedServer.echoTextArgument: "hi"]))

                #expect(await sink.displayEvents.isEmpty)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("with no ambient context, a result with an image gives the same text")
    func noContextGivesTheSameText() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [Self.imageTool], name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let output = try await MCPTestSupport.tool(named: Self.imageToolName, on: server)
                .call(arguments: GeneratedContent(properties: [:]))

            #expect(output == "\(Self.captionText)\n[image: \(Self.imageMimeType)]")
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a call in a runCode snippet posts the blocks under the runCode run")
    func runCodeSnippetPostsTheBlocks() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedMCPServer(
            serving: [Self.imageTool], name: Self.serverName)
        try await MCPTestSupport.withConnection(of: server) {
            let registry = try await MultiTool.Builder(mode: .open).withMCP(servers: [server]).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            try await withStubRun { run in
                let sink = RecordingEventSink()
                _ = try await run.context.mount(multiTool, as: .synchronous, postingTo: sink)
                    .call(
                        arguments: RunCodeArguments(
                            code: "return await tools.\(Self.serverName).\(Self.imageToolName)({});"))

                let events = await sink.displayEvents
                #expect(events.count == 1)
                #expect(events.first?.tool == multiTool.name)
                let content = try #require(
                    await Self.chunks(in: sink).first.flatMap(MCPToolContent.init(display:)))
                #expect(content.content == Self.imageBlocks)
            }
        }
        withExtendedLifetime(scripted) {}
    }

    @Test("a display part of another tool is not MCP tool content")
    func otherDisplayPartsAreNotMCPToolContent() {
        #expect(MCPToolContent(display: .text("x")) == nil)
        #expect(MCPToolContent(display: .json("{\"a\":1}")) == nil)
        #expect(MCPToolContent(display: .json("not json")) == nil)
        #expect(MCPToolContent(display: .diff(path: "/a", oldText: nil, newText: "")) == nil)
    }

    @Test("the display part of MCP tool content gives the same content again")
    func displayPartRoundTrips() {
        let content = MCPToolContent(content: Self.imageBlocks, isError: true)
        #expect(MCPToolContent(display: content.display) == content)
    }
}
