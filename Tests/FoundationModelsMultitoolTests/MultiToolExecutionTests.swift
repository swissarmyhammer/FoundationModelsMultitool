import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// M4a coverage for `MultiTool`: the `runCode` `Tool` conformance that wires
/// together every prior milestone — `JSCInterpreter` (M1), `ArgumentMarshaler`
/// + `ToolInvoker` (M3), `MultiTool.Builder` + `APISurface` (M2.5), and
/// `ResultRenderer` (M5) — into a single working execution path: `tools.*`
/// installed in a fresh sandbox per call, dispatching into real wrapped
/// `Tool`s. No model is needed for any of this; `RunCodeArguments` is built
/// directly, standing in for what a real agent loop (M4b) would decode.
@Suite("MultiToolExecution")
struct MultiToolExecutionTests {
    // MARK: - Composition: intermediates stay in the sandbox

    @Test("composing two tools in one snippet returns only the final value; intermediates never appear in the rendered output")
    func composedSnippetReturnsOnlyFinalValue() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                const cities = tools.cities().cities;
                const temps = cities.map(c => tools.temp({ city: c }).tempC);
                return Math.max(...temps);
                """)
        )

        #expect(output == "33")
        for intermediate in ["AAA", "BBB", "CCC", "11", "22"] {
            #expect(!output.contains(intermediate))
        }
    }

    // MARK: - Grouped-namespace dispatch

    @Test("tools.github.<name> dispatches to the correct grouped tool")
    func groupedCallDispatchesToCorrectTool() async throws {
        let registry = try MultiTool.Builder()
            .addGroup(named: "github", [IssueCountTool()])
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.github.issueCount({ repo: 'demo' }).count;")
        )

        #expect(output == "42")
    }

    // MARK: - The v1 async bridge (plan.md Resolved #1)

    @Test("an async (delayed) tool's result arrives through the blocking bridge, off the main thread")
    func delayedToolResolvesThroughTheBlockingBridge() async throws {
        let delayedTool = DelayedTool()
        let registry = try MultiTool.Builder()
            .addTool(delayedTool)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.delayed();"))

        #expect(output == "\"delayed-result\"")
        #expect(delayedTool.ranOnMainThread == false)
    }

    // MARK: - Mis-called tool: repairable error, not a crash

    @Test("a mis-called tool (missing required argument) surfaces ResultRenderer's repairable error text, not a crash")
    func misCalledToolSurfacesRepairableErrorText() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.temp({});"))

        #expect(output.contains("Fix the snippet and call runCode again."))
        #expect(output.contains("city"))
    }

    // MARK: - directMode(): a runCode-only surface

    @Test("registry.directMode() reports no findAPIs affordance; a plain registry reports both")
    func directModeReportsRunCodeOnlySurface() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        #expect(registry.isDirectMode == false)
        #expect(registry.supportsFindAPIs == true)
        #expect(registry.affordances == ["runCode", "findAPIs"])

        let direct = registry.directMode()

        #expect(direct.isDirectMode == true)
        #expect(direct.supportsFindAPIs == false)
        #expect(direct.affordances == ["runCode"])
        // `directMode()` only flips the affordance metadata — the executable
        // surface itself (and its rendered catalog) is unchanged.
        #expect(direct.surface.entries.map(\.path) == registry.surface.entries.map(\.path))
    }
}
