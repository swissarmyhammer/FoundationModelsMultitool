// `DynamicToolsetScenario` — a tool set that adds, re-schemas and removes a
// tool, one stage at a time.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/DynamicToolsetScenario.swift`.
// Test support — see the header of `ScriptedServer.swift`. The source
// scheduled its three stages on wall-clock timers. A test that read the
// catalog after one timer fired saw the next stage, and under machine load
// that read came late. Here a stage runs on a command: a test calls
// `advanceDynamicToolsetScenario()`, and the stage runs before the call
// returns. The `mcp-test-server` executable has no test to give that command,
// so `runDynamicToolsetStages(on:)` gives it on a clock — the real clock in
// the executable, and a clock the test controls in a test.

import MCP

extension ScriptedServer {
    /// The name of the tool the scenario re-schemas partway through —
    /// present from the start, still present at the end under the same name
    /// with a different `inputSchema`.
    public static let dynamicToolsetReschemadToolName = "counter"

    /// The name of the tool the scenario adds and later removes — the tool a
    /// consumer watches vanish, to see call-time resolution of a tool that is
    /// no longer served.
    public static let dynamicToolsetVanishingToolName = "greeter"

    /// How many milliseconds ``runDynamicToolsetStages(on:)`` waits before
    /// each stage.
    private static let dynamicToolsetStageDelayMilliseconds = 1500

    /// How long ``runDynamicToolsetStages(on:)`` waits before each stage —
    /// long enough that the `tools/list_changed` notification and re-list of
    /// one stage settle before the next stage runs.
    ///
    /// `public`, so that a test of the clock-driven stages can state the
    /// sleeps it expects.
    public static let dynamicToolsetStageDelay = Duration.milliseconds(dynamicToolsetStageDelayMilliseconds)

    /// How many stages the scenario has: add, re-schema, remove.
    public static var dynamicToolsetStageCount: Int {
        dynamicToolsetStages.count
    }

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

    /// The three stages of the scenario, in order.
    /// ``advanceDynamicToolsetScenario()`` runs one of them on each call.
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

    /// Registers the initial tool set of the scenario, and runs no stage.
    ///
    /// ``dynamicToolsetReschemadToolName`` (a no-argument tool) is registered
    /// up front, so it is in the first catalog snapshot. The three stages
    /// then wait for ``advanceDynamicToolsetScenario()``, or for the clock of
    /// ``runDynamicToolsetStages(on:)``:
    /// 1. **Add**: ``dynamicToolsetVanishingToolName`` joins the catalog.
    /// 2. **Re-schema**: ``dynamicToolsetReschemadToolName`` is re-declared
    ///    with ``reschemadCounterSchema`` in place of ``initialCounterSchema``
    ///    — same name, different `inputSchema`, so its fingerprint changes.
    /// 3. **Remove**: ``dynamicToolsetVanishingToolName`` leaves the catalog.
    ///
    /// Each stage sends `notifications/tools/list_changed` itself, so each
    /// one produces its own catalog snapshot when the caller lets the
    /// snapshot of one stage arrive before it runs the next.
    public func startDynamicToolsetScenario() {
        addScriptedTool(
            name: Self.dynamicToolsetReschemadToolName,
            description: "Advances a running count by one.",
            inputSchema: Self.initialCounterSchema
        ) { _ in
            CallTool.Result(content: [.text(text: "advanced by 1", annotations: nil, _meta: nil)])
        }
    }

    /// Runs the next stage of the scenario: its mutation, then its
    /// `notifications/tools/list_changed`.
    ///
    /// The stage is done when this returns, so the caller decides the order
    /// of the stages and what happens between them — no timer does.
    ///
    /// - Returns: `true` when a stage ran, or `false` when every stage
    ///   already ran.
    @discardableResult
    public func advanceDynamicToolsetScenario() async -> Bool {
        guard dynamicToolsetStagesRun < Self.dynamicToolsetStages.count else {
            return false
        }
        let stage = Self.dynamicToolsetStages[dynamicToolsetStagesRun]
        // Counted before the stage runs: the stage suspends, and a second
        // call that the actor takes in that gap must run the stage after it.
        dynamicToolsetStagesRun += 1
        await stage(self)
        return true
    }

    /// Runs each stage of the scenario that did not run yet, one
    /// ``dynamicToolsetStageDelay`` after the previous one, as `clock`
    /// measures it — the "on a timer" form the `mcp-test-server` executable
    /// serves.
    ///
    /// The task is unstructured on purpose, as the task of
    /// ``scheduleMutation(after:_:)`` is: the caller returns at once and
    /// observes the stages from the far side of the connection. The task
    /// ends by itself after the last stage, it ends early when its sleep
    /// throws, and it holds `self` weakly, so it never keeps a released
    /// server alive.
    ///
    /// - Parameter clock: The clock each wait sleeps on — `ContinuousClock`
    ///   in the executable, and a clock the test opens in a test.
    public func runDynamicToolsetStages(on clock: any Clock<Duration>) {
        Task { [weak self] in
            for _ in Self.dynamicToolsetStages {
                do {
                    try await clock.sleep(for: Self.dynamicToolsetStageDelay)
                } catch {
                    return
                }
                guard let self, await self.advanceDynamicToolsetScenario() else {
                    return
                }
            }
        }
    }
}
