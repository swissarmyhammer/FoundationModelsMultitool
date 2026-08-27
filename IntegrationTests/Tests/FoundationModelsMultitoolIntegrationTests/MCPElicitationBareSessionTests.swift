import Foundation
import FoundationModels
import FoundationModelsRouter
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// The bare-session scenario of a server-initiated elicitation: one MCP verb
/// that elicits mid-call, mounted on a plain `LanguageModelSession` with no
/// Router at all, and a host handler that answers.
///
/// `MCPTool` is a plain `Tool`: with no ambient `ToolContext`, the server
/// routes the `elicitation/create` of the loopback `elicitEcho` tool to the
/// `elicitationHandler` the host constructed the server with, and Apple's
/// tool call holds the turn while that handler answers. The verb then renders
/// the tool's result, whose structured content reflects the answer, and the
/// model reads the answer out of it. The root package's
/// `MCPElicitationTests` holds that contract with no model; this suite drives
/// it through a real one. `runBareSessionScenario` carries the model guard,
/// the session, and the assertion; this suite supplies the tool and the
/// prompt.
///
/// Serialized exactly like the other gated suites, and unreachable from the
/// root `swift test`, which declares no target for this nested
/// `IntegrationTests` package.
@Suite(
    "An MCP elicitation on a bare LanguageModelSession",
    .serialized,
    .timeLimit(.minutes(bareSessionTimeLimitMinutes))
)
struct MCPElicitationBareSessionTests {

    @Test("an eliciting MCP verb answers on a bare session with the value the host handler gave")
    func elicitingVerbAnswersWithTheHandlersValue() async throws {
        let scripted = ScriptedServer()
        await scripted.addLoopbackTools()
        let server = MCPServer(
            name: mcpElicitationBareSessionServerName,
            elicitationHandler: { _ in mcpElicitationBareSessionAnswer })
        try await server.connect(via: scripted.startOnInMemoryPair())
        let entry = try #require(await server.tool(named: ScriptedServer.elicitEchoToolName))
        let tool = MCPTool(entry: entry, server: server)

        try await runBareSessionScenario(
            named: mcpElicitationBareSessionScenarioName,
            tools: [tool],
            prompt: mcpElicitationBareSessionPrompt,
            marker: mcpElicitationBareSessionMarker)
        withExtendedLifetime(scripted) {}
    }
}

/// The label the printed result and skip lines carry.
private let mcpElicitationBareSessionScenarioName = "bareSessionMCPElicitation"

/// The name of the `MCPServer` the scenario connects.
private let mcpElicitationBareSessionServerName = "bare-session-mcp-elicitation-server"

/// The value the host handler answers, and the text the answer must carry.
private let mcpElicitationBareSessionMarker = "pelican"

/// The accept the host handler answers every request with: the marker under
/// the answer field the loopback tool requests.
private let mcpElicitationBareSessionAnswer = ElicitationResponse.accept(
    content: [ScriptedServer.elicitEchoAnswerField: .string(mcpElicitationBareSessionMarker)])

/// The request the model is given.
///
/// It names the tool and the field of its structured result, and asks for the
/// value word for word, so an answer that carries the marker is one the host
/// handler supplied.
private let mcpElicitationBareSessionPrompt =
    "Call the \(ScriptedServer.elicitEchoToolName) tool with no arguments, then reply with exactly "
    + "the value of \(ScriptedServer.elicitEchoAnswerField) in the structured result the tool reported."
