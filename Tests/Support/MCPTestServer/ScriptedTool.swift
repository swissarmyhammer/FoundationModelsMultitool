// `ScriptedTool` — one tool `ScriptedServer` serves.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/ScriptedTool.swift`. Test
// support — see the header of `ScriptedServer.swift`.

import MCP

/// One tool ``ScriptedServer`` can serve: its `tools/list` definition,
/// paired with the handler that answers `tools/call` for it.
///
/// A test scripts a new tool — or replaces one, see
/// ``ScriptedServer/replaceTool(_:)`` — by constructing one of these. The
/// factories of ``ScriptedServer`` build the same values.
public struct ScriptedTool: Sendable {
    /// The `tools/list` definition served for this tool.
    public let definition: MCP.Tool

    /// Answers `tools/call` for this tool.
    public let handler: @Sendable (CallTool.Parameters) async throws -> CallTool.Result

    /// Creates a scripted tool from a definition and its call handler.
    ///
    /// - Parameters:
    ///   - definition: The `tools/list` definition to serve.
    ///   - handler: The closure that answers `tools/call` for this tool.
    public init(
        definition: MCP.Tool,
        handler: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result
    ) {
        self.definition = definition
        self.handler = handler
    }
}
