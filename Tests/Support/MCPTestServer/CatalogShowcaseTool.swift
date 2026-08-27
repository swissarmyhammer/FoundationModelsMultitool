// `CatalogShowcaseTool` — one tool that fills every catalog-facing field.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/CatalogShowcaseTool.swift`.
// Test support — see the header of `ScriptedServer.swift`. The catalog it
// showcases is `MCPToolCatalog` in `Capabilities/MCP`.

import MCP

extension ScriptedServer {
    /// The default name of ``catalogShowcaseTool(named:)``.
    public static let catalogShowcaseToolName = "weather_lookup"

    /// The input schema of ``catalogShowcaseTool(named:)``: a required `city`
    /// string and an optional `units` string with two enum values — richer
    /// than the one property of ``echoTool(named:description:)``, so a
    /// catalog consumer has more than one property to render.
    private static let catalogShowcaseInputSchema: Value = JSONSchemaBuilder.object(
        properties: [
            "city": JSONSchemaBuilder.string(description: "The city to look up."),
            "units": .object([
                "type": .string("string"),
                "description": .string("The temperature units to report in."),
                "enum": .array([.string("celsius"), .string("fahrenheit")]),
            ]),
        ],
        required: ["city"]
    )

    /// The operational hints of the tool — every `MCP.Tool.Annotations`
    /// field set to a non-default value, so a catalog consumer has something
    /// concrete for each one.
    private static let catalogShowcaseAnnotations = MCP.Tool.Annotations(
        title: "Weather Lookup",
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: true
    )

    /// The icon set of the tool — one sized icon, so a catalog consumer has a
    /// non-empty `icons` array.
    private static let catalogShowcaseIcons: [MCP.Icon] = [
        MCP.Icon(src: "https://example.com/icons/weather.png", mimeType: "image/png", sizes: ["48x48"])
    ]

    /// Builds a tool that fills every catalog-facing field `MCPCatalogEntry`
    /// exposes — `title`, full annotations, icons and a multi-property
    /// `inputSchema` — unlike the echo tool and the filesystem tools, which
    /// leave `title`, `annotations` and `icons` at their empty defaults.
    ///
    /// - Parameter name: The tool name. Defaults to
    ///   ``catalogShowcaseToolName``.
    /// - Returns: The constructed ``ScriptedTool``.
    public static func catalogShowcaseTool(named name: String = catalogShowcaseToolName) -> ScriptedTool {
        let definition = MCP.Tool(
            name: name,
            title: "Weather Lookup",
            description: "Looks up the current weather for a city.",
            inputSchema: catalogShowcaseInputSchema,
            annotations: catalogShowcaseAnnotations,
            icons: catalogShowcaseIcons
        )
        let handler: @Sendable (CallTool.Parameters) async throws -> CallTool.Result = { params in
            let city = params.arguments?["city"]?.stringValue ?? "an unknown city"
            let units = params.arguments?["units"]?.stringValue ?? "celsius"
            return CallTool.Result(
                content: [.text(text: "The weather in \(city) is a mild 21 degrees \(units).", annotations: nil, _meta: nil)]
            )
        }
        return ScriptedTool(definition: definition, handler: handler)
    }

    /// Registers ``catalogShowcaseTool(named:)`` on this server — the tool
    /// set of ``ServerMode/catalog``.
    ///
    /// - Parameter name: The tool name. Defaults to
    ///   ``catalogShowcaseToolName``.
    public func addCatalogShowcaseTool(named name: String = ScriptedServer.catalogShowcaseToolName) {
        addTool(Self.catalogShowcaseTool(named: name))
    }
}
