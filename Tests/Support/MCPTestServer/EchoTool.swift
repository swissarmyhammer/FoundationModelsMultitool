// `EchoTool` — the one-argument echo tool, the simplest scripted tool.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/EchoTool.swift`. Test
// support — see the header of `ScriptedServer.swift`.

import MCP

extension ScriptedServer {
    /// The default name of ``echoTool(named:description:)`` — and the first
    /// of the three loopback tool names, see ``addLoopbackTools()``.
    public static let echoToolName = "echo"

    /// The default description of ``echoTool(named:description:)``.
    public static let echoToolDescription = "Echoes the provided text back verbatim."

    /// The one argument of the echo tool: the text to echo.
    public static let echoTextArgument = "text"

    /// The input schema of ``echoTool(named:description:)``: one required
    /// string property, ``echoTextArgument``.
    private static let echoInputSchema: Value = JSONSchemaBuilder.object(
        properties: [echoTextArgument: JSONSchemaBuilder.string(description: "The text to echo back.")],
        required: [echoTextArgument]
    )

    /// Builds a tool that echoes its `text` argument back verbatim as its
    /// only content.
    ///
    /// A static factory, and not only an instance method, so a test can mint
    /// distinct fixture tools from it — the pagination self-test names
    /// several to fill more than one `tools/list` page.
    ///
    /// - Parameters:
    ///   - name: The tool name. Defaults to ``echoToolName``.
    ///   - description: The tool description. Defaults to
    ///     ``echoToolDescription``.
    /// - Returns: The constructed ``ScriptedTool``.
    public static func echoTool(
        named name: String = echoToolName,
        description: String = echoToolDescription
    ) -> ScriptedTool {
        let definition = MCP.Tool(
            name: name,
            description: description,
            inputSchema: echoInputSchema
        )
        let handler: @Sendable (CallTool.Parameters) async throws -> CallTool.Result = { params in
            let text = params.arguments?[echoTextArgument]?.stringValue ?? ""
            return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        }
        return ScriptedTool(definition: definition, handler: handler)
    }

    /// Registers ``echoTool(named:description:)`` on this server.
    ///
    /// - Parameters:
    ///   - name: The tool name. Defaults to ``echoToolName``.
    ///   - description: The tool description. Defaults to
    ///     ``echoToolDescription``.
    public func addEchoTool(
        named name: String = ScriptedServer.echoToolName,
        description: String = ScriptedServer.echoToolDescription
    ) {
        addTool(Self.echoTool(named: name, description: description))
    }
}
