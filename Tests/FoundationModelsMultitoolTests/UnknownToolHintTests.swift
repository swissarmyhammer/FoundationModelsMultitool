import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the did-you-mean repair hint: when a snippet calls a
/// `tools.*` path (or bare function) that does not exist, the rendered
/// error steers the model to the closest real catalog entries — turning
/// the wrong-guess dead end into a self-repair ramp — instead of leaving
/// only JavaScriptCore's bare `TypeError` text.
@Suite("UnknownToolHint")
struct UnknownToolHintTests {
    // MARK: - Unknown tools.* path: closest real path suggested

    @Test("calling an unknown tools.* name suggests the closest real path")
    func unknownToolsCallSuggestsClosestRealPath() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.getCities();")
        )

        #expect(output.contains("tools.getCities does not exist"))
        #expect(output.contains("tools.cities"))
        #expect(output.contains("Fix the snippet and call runCode again."))
    }

    // MARK: - Invented sub-path on a real tool

    @Test("calling an invented sub-path on a real tool suggests the real tool itself")
    func inventedSubPathSuggestsTheRealTool() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.temp.getCurrent({ city: 'ATX' });")
        )

        #expect(output.contains("tools.temp.getCurrent does not exist"))
        #expect(output.contains("tools.temp"))
    }

    // MARK: - No close match: steer back to findAPIs

    @Test("an unknown name with no close catalog match steers back to findAPIs")
    func unknownNameWithNoCloseMatchSteersToFindAPIs() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.sendEmail({ to: 'a@b.c' });")
        )

        #expect(output.contains("tools.sendEmail does not exist"))
        #expect(output.contains("findAPIs"))
    }

    // MARK: - Guard: a mis-called *existing* tool gets no did-you-mean noise

    @Test("a mis-called existing tool keeps its plain repairable error, with no does-not-exist hint")
    func misCalledExistingToolGetsNoHint() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.temp({});"))

        #expect(!output.contains("does not exist"))
        #expect(output.contains("Fix the snippet and call runCode again."))
    }
}
