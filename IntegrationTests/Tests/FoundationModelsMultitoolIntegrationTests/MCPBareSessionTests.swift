import Foundation
import FoundationModels
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// The bare-session scenario: one MCP verb mounted on a plain
/// `LanguageModelSession` with no Router at all.
///
/// `MCPTool` is a plain `Tool`: with no ambient `ToolContext`, the server's
/// call runs to completion under its own bare-call timeout, and the verb
/// answers the rendered result; the model then reads the echoed text out of
/// that result and repeats it. The root package's `MCPToolTests` holds that
/// contract with no model; this suite drives it through a real one.
/// `runBareSessionScenario` carries the model guard, the session, and the
/// assertion; this suite supplies the tool and the prompt.
///
/// The server is a `ScriptedServer` of the `MCPTestServer` product, served
/// in-process over an in-memory transport pair, so no subprocess and no
/// socket stand in the path.
///
/// Serialized exactly like the other gated suites, and unreachable from the
/// root `swift test`, which declares no target for this nested
/// `IntegrationTests` package.
@Suite(
    "An MCP verb on a bare LanguageModelSession",
    .serialized,
    .timeLimit(.minutes(bareSessionTimeLimitMinutes))
)
struct MCPBareSessionTests {

    @Test("an MCP echo verb answers on a bare session, and the answer carries the server's result")
    func echoVerbAnswersOnABareSession() async throws {
        let scripted = ScriptedServer()
        await scripted.addEchoTool()
        let server = MCPServer(name: mcpBareSessionServerName)
        try await server.connect(via: scripted.startOnInMemoryPair())
        let entry = try #require(await server.tool(named: ScriptedServer.echoToolName))
        let tool = MCPTool(entry: entry, server: server)

        try await runBareSessionScenario(
            named: mcpBareSessionScenarioName,
            tools: [tool],
            prompt: mcpBareSessionPrompt,
            marker: mcpBareSessionMarker)
        withExtendedLifetime(scripted) {}
    }
}

/// The label the printed result and skip lines carry.
private let mcpBareSessionScenarioName = "bareSessionMCPEcho"

/// The name of the `MCPServer` the scenario connects.
private let mcpBareSessionServerName = "bare-session-mcp-server"

/// The text the echo tool answers, and the text the answer must carry.
private let mcpBareSessionMarker = "pelican"

/// The request the model is given.
///
/// It names the tool and its one argument, and asks for the answer word for
/// word, so an answer that carries the marker is one the tool's result
/// supplied.
private let mcpBareSessionPrompt =
    "Use the \(ScriptedServer.echoToolName) tool with \(ScriptedServer.echoTextArgument) set to "
    + "\(mcpBareSessionMarker), then reply with exactly the text the tool answered."
