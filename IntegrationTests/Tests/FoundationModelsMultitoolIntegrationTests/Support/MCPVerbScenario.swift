import FoundationModels
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Runs one bare-session scenario for one verb of a connected `MCPServer`.
///
/// The MCP bare-session suites call this one function, thus the server
/// teardown, the tool lookup, the `MCPTool` build, and the scenario call are
/// written one time. Each caller keeps its own `ScriptedServer` and
/// `MCPServer` setup, and supplies only the values that differ.
///
/// The server is disconnected when the scenario ends, also when it throws or
/// a requirement fails (test rule T1).
///
/// - Parameters:
///   - server: the connected server that serves the verb.
///   - toolName: the name of the server tool to mount as the verb.
///   - scenarioName: the label the printed result, tool, and skip lines carry.
///   - prompt: the request the model is given.
///   - marker: the text the answer must carry, which only the tool's report
///     supplies.
/// - Throws: when the server has no tool with `toolName`, or what
///   `runBareSessionScenario(named:tools:prompt:marker:)` throws, after the
///   disconnect.
func runMCPVerbScenario(
    server: MCPServer,
    toolName: String,
    scenarioName: String,
    prompt: String,
    marker: String
) async throws {
    try await DisconnectScope.disconnecting([server]) {
        let entry = try #require(await server.tool(named: toolName))
        let tool = MCPTool(entry: entry, server: server)
        try await runBareSessionScenario(
            named: scenarioName,
            tools: [tool],
            prompt: prompt,
            marker: marker)
    }
}
