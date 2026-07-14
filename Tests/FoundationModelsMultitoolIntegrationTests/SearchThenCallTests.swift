import Testing

@testable import FoundationModelsMultitool

/// The gated real-model suite: the four sample MultiTools scenarios,
/// retargeted at a native `LanguageModelSession(tools: [multiTool,
/// findAPIsTool])`-driven run — "this is where the plan's empirical
/// search-then-call behavior is proven against real hardware."
///
/// **Native design.** Ported off `MultiToolAgent`'s hand-rolled ReAct loop
/// (`TurnFormat`/`AgentStep`, retired alongside it — see the `7840f24` kanban
/// task): every scenario now drives `runNativeIntegrationScenario` (`Support/
/// ScenarioRunner.swift`), which builds a real `MLXLanguageModel` +
/// `LanguageModelSession` and lets Apple's own native tool-calling loop
/// decide when to call `findAPIs` vs `runCode`. There is no turn-format
/// matrix anymore — `.tolerantParse`/`.guided` were `MultiToolAgent`-specific
/// prompted-text conventions with no equivalent in native tool-calling — so
/// each scenario now runs once, not twice.
///
/// **Known upstream dependency.** Multi-tool-call composition (`findAPIs`
/// then `runCode` in the same `respond(to:)` round) depends on
/// `mlx-swift-lm`'s own multi-turn tool-calling fix (task `qp8q4h9`, see
/// `f329qvr`'s and `4aveepp`'s task descriptions): if that fix hasn't landed
/// in the resolved `mlx-swift-lm` checkout, a scenario expecting
/// `findAPIs` -> `runCode` composition is expected to fail in a specific,
/// diagnosable way — the session falls through to plain text after the
/// first tool call, so `findAPIsPrecedesRunCode`/`invokedToolPaths` don't
/// see a `runCode` call at all. See this suite's go/no-go task comment for
/// the actual observed pass rate on real hardware.
///
/// Every test is `.enabled(if: multitoolIntegrationEnabled)`: unset
/// `MULTITOOL_INTEGRATION`, the whole suite is skipped — zero downloads,
/// zero live inference — so `swift test` stays green on a network/GPU-less
/// box (the default posture of this environment). `.serialized` mirrors
/// Router's own gated suite: only one profile is resident at a time per
/// `Router`, and real weight loading is heavy enough that running the four
/// scenarios one at a time, under a generous `.timeLimit`, is the sane
/// default even though each test resolves its own fresh `Router`.
@Suite(
    "Gated search-then-call scenarios (M6.5a)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct SearchThenCallTests {
    // MARK: - Scenario 1: single-call `weather`

    @Test("single-call weather scenario finds and calls tools.weather")
    func singleCallWeather() async throws {
        try await runNativeIntegrationScenario(
            name: "singleCallWeather",
            tools: [IntegrationWeatherTool()],
            prompt: "How warm is it in Austin right now?",
            expectFindApis: true,
            expectedToolPaths: ["weather"]
        )
    }

    // MARK: - Scenario 2: compose/chain tripCities -> weather -> warmest

    @Test("compose/chain scenario writes one snippet composing tripCities and weather")
    func composeChain() async throws {
        try await runNativeIntegrationScenario(
            name: "composeChain",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            prompt: "Of the cities on my trip, which is warmest right now?",
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"]
        )
    }

    // MARK: - Scenario 3: discovery under ~20 distractors

    @Test("discovery scenario's findAPIs selects only the 2 relevant tools among ~20")
    func discoveryUnderDistractors() async throws {
        try await runNativeIntegrationScenario(
            name: "discoveryUnderDistractors",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            prompt: "Of the cities on my trip, which is warmest right now?",
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"],
            expectedFoundApiNames: ["tripCities", "weather"]
        )
    }

    // MARK: - Scenario 4: repair from a trip-prone tool

    @Test("repair scenario recovers from a mis-called booking tool within a bounded number of calls")
    func repairFromTripProneTool() async throws {
        try await runNativeIntegrationScenario(
            name: "repairFromTripProneTool",
            tools: [IntegrationBookingTool()],
            prompt: "Confirm my booking, id 42.",
            expectFindApis: false,
            expectedToolPaths: ["book"],
            maxRunCodeCallsBeforeFinal: 3
        )
    }
}
