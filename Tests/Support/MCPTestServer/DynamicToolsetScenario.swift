// `DynamicToolsetScenario` — a tool set that adds, re-schemas and removes a
// tool on a timer.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/DynamicToolsetScenario.swift`.
// Test support — see the header of `ScriptedServer.swift`. The source
// scheduled its three stages as three calls with the multipliers written
// out; here the stages are one table, and the loop computes each delay.

import MCP

extension ScriptedServer {
    /// The name of the tool ``startDynamicToolsetScenario()`` re-schemas
    /// partway through — present from the start, still present at the end
    /// under the same name with a different `inputSchema`.
    public static let dynamicToolsetReschemadToolName = "counter"

    /// The name of the tool ``startDynamicToolsetScenario()`` adds and later
    /// removes — the tool a consumer watches vanish, to see call-time
    /// resolution of a tool that is no longer served.
    public static let dynamicToolsetVanishingToolName = "greeter"

    /// How many milliseconds ``startDynamicToolsetScenario()`` waits between
    /// stages.
    private static let dynamicToolsetStageDelayMilliseconds = 1500

    /// How long ``startDynamicToolsetScenario()`` waits between stages —
    /// long enough that the `tools/list_changed` notification and re-list of
    /// one stage settle before the next stage fires.
    private static let dynamicToolsetStageDelay = Duration.milliseconds(dynamicToolsetStageDelayMilliseconds)

    /// The `inputSchema` ``dynamicToolsetReschemadToolName`` starts with — no
    /// arguments.
    private static let initialCounterSchema = JSONSchemaBuilder.emptySchema

    /// The `inputSchema` ``dynamicToolsetReschemadToolName`` is re-declared
    /// with partway through: a required `step` integer, structurally
    /// different from ``initialCounterSchema`` — the same-name schema change
    /// `MCPToolCatalog.diff(from:)` reports as changed.
    private static let reschemadCounterSchema: Value = JSONSchemaBuilder.object(
        properties: [
            "step": .object([
                "type": .string("integer"),
                "description": .string("How many counts to advance by."),
            ])
        ],
        required: ["step"]
    )

    /// The three timed stages of ``startDynamicToolsetScenario()``, in
    /// order. Stage N fires N stage delays after the start.
    private static let dynamicToolsetStages: [@Sendable (ScriptedServer) async -> Void] = [
        // Add: the vanishing tool joins the catalog.
        { server in
            await server.addEchoTool(
                named: dynamicToolsetVanishingToolName, description: "Greets the caller by echoing a greeting.")
            try? await server.emitToolListChanged()
        },
        // Re-schema: the counter is re-declared with a different inputSchema.
        { server in
            await server.replaceTool(reschemadCounterTool())
            try? await server.emitToolListChanged()
        },
        // Remove: the vanishing tool leaves the catalog.
        { server in
            await server.removeTool(named: dynamicToolsetVanishingToolName)
            try? await server.emitToolListChanged()
        },
    ]

    /// Builds the re-declared ``dynamicToolsetReschemadToolName`` tool the
    /// scenario swaps in through ``replaceTool(_:)``.
    ///
    /// - Returns: The replacement ``ScriptedTool``, still named
    ///   ``dynamicToolsetReschemadToolName``.
    private static func reschemadCounterTool() -> ScriptedTool {
        let definition = MCP.Tool(
            name: dynamicToolsetReschemadToolName,
            description: "Advances a running count by a caller-supplied step.",
            inputSchema: reschemadCounterSchema
        )
        let handler: @Sendable (CallTool.Parameters) async throws -> CallTool.Result = { params in
            let step = params.arguments?["step"]?.intValue ?? 0
            return CallTool.Result(content: [.text(text: "advanced by \(step)", annotations: nil, _meta: nil)])
        }
        return ScriptedTool(definition: definition, handler: handler)
    }

    /// Registers the initial tool set, then schedules three timed mutations
    /// — a server that adds, re-schemas and removes a tool on a timer.
    ///
    /// ``dynamicToolsetReschemadToolName`` (a no-argument tool) is registered
    /// up front, so it is in the first catalog snapshot. The three stages of
    /// ``dynamicToolsetStages`` then fire in sequence, each
    /// ``dynamicToolsetStageDelay`` after the previous one:
    /// 1. **Add**: ``dynamicToolsetVanishingToolName`` joins the catalog.
    /// 2. **Re-schema**: ``dynamicToolsetReschemadToolName`` is re-declared
    ///    with ``reschemadCounterSchema`` in place of ``initialCounterSchema``
    ///    — same name, different `inputSchema`, so its fingerprint changes.
    /// 3. **Remove**: ``dynamicToolsetVanishingToolName`` leaves the catalog.
    ///
    /// Each stage sends `notifications/tools/list_changed` itself, so each
    /// one produces its own catalog snapshot.
    public func startDynamicToolsetScenario() {
        addScriptedTool(
            name: Self.dynamicToolsetReschemadToolName,
            description: "Advances a running count by one.",
            inputSchema: Self.initialCounterSchema
        ) { _ in
            CallTool.Result(content: [.text(text: "advanced by 1", annotations: nil, _meta: nil)])
        }

        for (index, stage) in Self.dynamicToolsetStages.enumerated() {
            scheduleMutation(after: Self.dynamicToolsetStageDelay * (index + 1), stage)
        }
    }
}
