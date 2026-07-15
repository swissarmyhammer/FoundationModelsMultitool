import Testing

@testable import FoundationModelsMultitool

/// The gated real-model suite: the four sample MultiTools scenarios,
/// retargeted at a native `LanguageModelSession(tools: [multiTool,
/// findAPIsTool])`-driven run — "this is where the plan's empirical
/// search-then-call behavior is proven against real hardware."
///
/// **Outcome over path.** Each scenario passes when the model produces a
/// valid, grounded answer — see `runNativeIntegrationScenario`'s
/// documentation for the exact three assertions and why route assertions
/// (tool ordering, exact call sets, call budgets) were retired in favor of
/// diagnostics. The `answerContainsOneOf` values below are the fixtures'
/// own distinctive data (`Fixtures/ScenarioTools.swift`): the weather
/// fixture always returns 31°C, the trip is always ATX → SFO → NYC, and the
/// booking fixture confirms id 42 only when genuinely called with
/// `confirm: true` — values a hallucinating model has never guessed across
/// the many recorded runs on task `k4mj1gm` (it said 72°F, 25°C, Tokyo,
/// Bangkok, Miami — never 31, never the fixture cities).
///
/// **Native design.** Ported off `MultiToolAgent`'s hand-rolled ReAct loop
/// (`TurnFormat`/`AgentStep`, retired alongside it — see the `7840f24` kanban
/// task): every scenario drives `runNativeIntegrationScenario` (`Support/
/// ScenarioRunner.swift`), which builds a real `MLXLanguageModel` +
/// `LanguageModelSession` and lets Apple's own native tool-calling loop
/// decide when to call `findAPIs` vs `runCode`. There is no turn-format
/// matrix anymore — `.tolerantParse`/`.guided` were `MultiToolAgent`-specific
/// prompted-text conventions with no equivalent in native tool-calling — so
/// each scenario runs once, not twice.
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
    /// The valid answers to "which trip city is warmest": the fixture trip
    /// is always ATX → SFO → NYC and the weather fixture returns the same
    /// 31°C for every city, so *any* fixture city — IATA code or the
    /// spelled-out name models routinely expand codes to — is a correct,
    /// grounded answer, and any other city is a hallucination.
    private static let fixtureCityAnswers = [
        "ATX", "Austin",
        "SFO", "San Francisco",
        "NYC", "New York",
    ]

    // MARK: - Scenario 1: single-call `weather`

    @Test("single-call weather scenario answers with the fixture's real temperature")
    func singleCallWeather() async throws {
        try await runNativeIntegrationScenario(
            name: "singleCallWeather",
            tools: [IntegrationWeatherTool()],
            prompt: "How warm is it in Austin right now?",
            // The weather fixture always returns tempC 31 — a value no
            // hallucinated forecast has ever produced (72°F, 25°C, 22°C
            // were the observed inventions).
            answerContainsOneOf: ["31"]
        )
    }

    // MARK: - Scenario 2: compose/chain tripCities -> weather -> warmest

    @Test("compose/chain scenario names a real fixture trip city as warmest")
    func composeChain() async throws {
        try await runNativeIntegrationScenario(
            name: "composeChain",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            prompt: "Of the cities on my trip, which is warmest right now?",
            answerContainsOneOf: Self.fixtureCityAnswers
        )
    }

    // MARK: - Scenario 3: discovery under ~20 distractors

    @Test("discovery scenario still answers with a real fixture trip city among ~20 distractor tools")
    func discoveryUnderDistractors() async throws {
        try await runNativeIntegrationScenario(
            name: "discoveryUnderDistractors",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            prompt: "Of the cities on my trip, which is warmest right now?",
            answerContainsOneOf: Self.fixtureCityAnswers
        )
    }

    // MARK: - Scenario 4: repair from a trip-prone tool

    @Test("repair scenario genuinely confirms the booking, however many attempts it takes")
    func repairFromTripProneTool() async throws {
        try await runNativeIntegrationScenario(
            name: "repairFromTripProneTool",
            tools: [IntegrationBookingTool()],
            prompt: "Confirm my booking, id 42.",
            answerContainsOneOf: ["confirm"],
            // "I was unable to confirm…" embeds the required word inside a
            // failure phrasing — a valid answer affirms the confirmation,
            // it doesn't report failing at it.
            answerMustNotContain: ["unable", "couldn't", "cannot", "can't", "not able"],
            // "Your booking is confirmed" claims a side effect — the
            // trip-prone `book` tool must genuinely have been invoked (any
            // number of repair attempts, any route) for that claim to be
            // true.
            mustInvoke: ["book"]
        )
    }
}
