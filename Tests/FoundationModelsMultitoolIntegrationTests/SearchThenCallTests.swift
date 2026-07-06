import Testing

@testable import FoundationModelsMultitool

/// M6.5a's gated real-model suite: the four sample MultiTools from plan.md
/// M6.5, each run under both turn formats (`.tolerantParse` from M4b,
/// `.guided` from M4c) — "this is where the plan's empirical turn-format
/// decision is settled and recorded."
///
/// Every test is `.enabled(if: multitoolIntegrationEnabled)`: unset
/// `MULTITOOL_INTEGRATION`, the whole suite is skipped — zero downloads,
/// zero live inference — so `swift test` stays green on a network/GPU-less
/// box (the default posture of this environment). `.serialized` mirrors
/// Router's own gated suite: only one profile is resident at a time per
/// `Router`, and real weight loading is heavy enough that running the eight
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

    @Test("single-call weather scenario finds and calls tools.weather, under .tolerantParse")
    func singleCallWeatherTolerantParse() async throws {
        try await runIntegrationScenario(
            name: "singleCallWeather/tolerantParse",
            tools: [IntegrationWeatherTool()],
            prompt: "How warm is it in Austin right now?",
            turnFormat: .tolerantParse(),
            expectFindApis: true,
            expectedToolPaths: ["weather"]
        )
    }

    @Test("single-call weather scenario finds and calls tools.weather, under .guided")
    func singleCallWeatherGuided() async throws {
        try await runIntegrationScenario(
            name: "singleCallWeather/guided",
            tools: [IntegrationWeatherTool()],
            prompt: "How warm is it in Austin right now?",
            turnFormat: .guided(),
            expectFindApis: true,
            expectedToolPaths: ["weather"]
        )
    }

    // MARK: - Scenario 2: compose/chain tripCities -> weather -> warmest

    @Test("compose/chain scenario writes one snippet composing tripCities and weather, under .tolerantParse")
    func composeChainTolerantParse() async throws {
        try await runIntegrationScenario(
            name: "composeChain/tolerantParse",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            prompt: "Of the cities on my trip, which is warmest right now?",
            turnFormat: .tolerantParse(),
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"]
        )
    }

    @Test("compose/chain scenario writes one snippet composing tripCities and weather, under .guided")
    func composeChainGuided() async throws {
        try await runIntegrationScenario(
            name: "composeChain/guided",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            prompt: "Of the cities on my trip, which is warmest right now?",
            turnFormat: .guided(),
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"]
        )
    }

    // MARK: - Scenario 3: discovery under ~20 distractors

    @Test("discovery scenario's findAPIs selects only the 2 relevant tools among ~20, under .tolerantParse")
    func discoveryUnderDistractorsTolerantParse() async throws {
        try await runIntegrationScenario(
            name: "discoveryUnderDistractors/tolerantParse",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            prompt: "Of the cities on my trip, which is warmest right now?",
            turnFormat: .tolerantParse(),
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"],
            expectedFoundApiNames: ["tripCities", "weather"]
        )
    }

    @Test("discovery scenario's findAPIs selects only the 2 relevant tools among ~20, under .guided")
    func discoveryUnderDistractorsGuided() async throws {
        try await runIntegrationScenario(
            name: "discoveryUnderDistractors/guided",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            prompt: "Of the cities on my trip, which is warmest right now?",
            turnFormat: .guided(),
            expectFindApis: true,
            expectedToolPaths: ["tripCities", "weather"],
            expectedFoundApiNames: ["tripCities", "weather"]
        )
    }

    // MARK: - Scenario 4: repair from a trip-prone tool

    @Test("repair scenario recovers from a mis-called booking tool within a bounded number of turns, under .tolerantParse")
    func repairFromTripProneToolTolerantParse() async throws {
        try await runIntegrationScenario(
            name: "repairFromTripProneTool/tolerantParse",
            tools: [IntegrationBookingTool()],
            prompt: "Confirm my booking, id 42.",
            turnFormat: .tolerantParse(),
            expectFindApis: false,
            expectedToolPaths: ["book"],
            maxRunCodeStepsBeforeFinal: 3
        )
    }

    @Test("repair scenario recovers from a mis-called booking tool within a bounded number of turns, under .guided")
    func repairFromTripProneToolGuided() async throws {
        try await runIntegrationScenario(
            name: "repairFromTripProneTool/guided",
            tools: [IntegrationBookingTool()],
            prompt: "Confirm my booking, id 42.",
            turnFormat: .guided(),
            expectFindApis: false,
            expectedToolPaths: ["book"],
            maxRunCodeStepsBeforeFinal: 3
        )
    }
}
