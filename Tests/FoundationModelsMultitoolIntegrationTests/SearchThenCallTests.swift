import Testing

@testable import FoundationModelsMultitool

/// The gated real-model suite: the four sample MultiTools scenarios,
/// retargeted at the shipped host contract — the tools
/// `MultiTool.Registry.makeSessionTools(librarian:)` vends, mounted on a
/// `RoutedSession` and driven by draining `streamEvents(to:)` — "this is where
/// the plan's empirical search-then-call behavior is proven against real
/// hardware."
///
/// **Outcome over path.** Each scenario passes when the model produces a
/// valid, grounded answer — see `runNativeIntegrationScenario`'s
/// documentation for the exact assertions and why route assertions
/// (tool ordering, exact call sets, call budgets) were retired in favor of
/// diagnostics. The `answerContainsOneOf` values below are the fixtures'
/// own distinctive data (`Fixtures/ScenarioTools.swift`), read from those
/// fixtures rather than restated here: `IntegrationScenarioAnswers` derives
/// both the single-call reading and the one warmest trip city from
/// `integrationCityWeather`, and the booking fixture confirms id 42 only
/// when genuinely called with `confirm: true`. These are values a
/// hallucinating model has never guessed across the many recorded runs on
/// task `k4mj1gm` (it said 72°F, 25°C, Tokyo, Bangkok, Miami — never the
/// fixture's own reading, never the fixture cities).
///
/// Each scenario also states what its answer must be *grounded in*, as
/// `groundedIn: IntegrationScenarioGrounding.<question>` — the `tools.*`
/// returns that answer depends on, declared beside the readings rather than
/// spelled out here. A reply in the accepted form is not evidence on its own:
/// a recorded discovery run named the warmest city having fetched only the
/// itinerary, which no run can know, and it passed (task `0981ar3`).
///
/// **Native design.** Ported off `MultiToolAgent`'s hand-rolled ReAct loop
/// (`TurnFormat`/`AgentStep`, retired alongside it — see the `7840f24` kanban
/// task): every scenario drives `runNativeIntegrationScenario` (`Support/
/// ScenarioRunner.swift`), which mounts the vended tools on the
/// `RoutedSession` a resolved profile slot vends and lets that session's own
/// native tool-calling loop decide when to call `searchTools` vs `runCode`,
/// reading the turn off `streamEvents(to:)`. There is no turn-format
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
    // MARK: - Scenario 1: single-call `getWeather`

    @Test("single-call weather scenario answers with the fixture's real temperature")
    func singleCallWeather() async throws {
        try await runNativeIntegrationScenario(
            name: "singleCallWeather",
            tools: { log in [IntegrationWeatherTool(log: log)] },
            // Both the city this asks about and the temperature it grades on
            // are read from `integrationSingleCallCity`, so editing a reading
            // moves the question and the answer together. Stating either as a
            // literal is what let this scenario grade `"31"` against a fixture
            // that had stopped reporting 31 — the drift the human ruling of
            // 2026-08-07 (task `tkrdwb8`) removed from the compose scenario
            // and this one inherited.
            prompt: "How warm is it in \(integrationSingleCallCity.name) right now?",
            // The fixture's own reading — a value no hallucinated forecast has
            // ever produced (72°F, 25°C, 22°C were the observed inventions).
            // `integrationSingleCallCity` is never the warmest trip city, and
            // `IntegrationScenarioAnswers` enforces that this reading shares no
            // substring with the warmest-city answers, so a reply that passes
            // here cannot also pass the compose and discovery scenarios.
            answerContainsOneOf: IntegrationScenarioAnswers.singleCall,
            // A reading, because that is what "how warm is it there" asks for:
            // the city's own name is in the prompt already, so nothing about
            // the reply proves a temperature was fetched except the fetch.
            groundedIn: IntegrationScenarioGrounding.singleCall
        )
    }

    // MARK: - Scenario 2: compose/chain getTrip -> getWeather -> warmest

    @Test("compose/chain scenario names the fixture's single warmest trip city")
    func composeChain() async throws {
        try await runNativeIntegrationScenario(
            name: "composeChain",
            tools: { log in [IntegrationTripTool(log: log), IntegrationWeatherTool(log: log)] },
            prompt: "Of the cities on my trip, which is warmest right now?",
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // The itinerary *and* a reading: which cities are candidates comes
            // from one, which of them is warmest from the other. A trip-only
            // run that names a city is guessing.
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }

    // MARK: - Scenario 3: discovery under distractors

    @Test("discovery scenario still names the warmest trip city among the distractor tools")
    func discoveryUnderDistractors() async throws {
        try await runNativeIntegrationScenario(
            name: "discoveryUnderDistractors",
            tools: { log in
                [IntegrationWeatherTool(log: log), IntegrationTripTool(log: log)]
                    + integrationDistractorTools(log: log)
            },
            prompt: "Of the cities on my trip, which is warmest right now?",
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // The same question, so the same dependency — the distractors
            // change how hard the two relevant tools are to find, not what the
            // answer rests on. This is the scenario whose recorded run named
            // the warmest city off the itinerary alone (task `0981ar3`).
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }

    // MARK: - Scenario 4: repair from a trip-prone tool

    @Test("repair scenario genuinely confirms the booking, however many attempts it takes")
    func repairFromTripProneTool() async throws {
        try await runNativeIntegrationScenario(
            name: "repairFromTripProneTool",
            tools: { log in [IntegrationBookingTool(log: log)] },
            prompt: "Confirm my booking, id 42.",
            answerContainsOneOf: ["confirm"],
            // "I was unable to confirm…" embeds the required word inside a
            // failure phrasing — a valid answer affirms the confirmation,
            // it doesn't report failing at it.
            answerMustNotContain: ["unable", "couldn't", "cannot", "can't", "not able"],
            // The confirmation itself, because that is the whole content of
            // this answer: "your booking is confirmed" claims a side effect,
            // and `confirmBooking` must genuinely have returned a confirmation
            // (after any number of repair attempts, by any route) for the
            // claim to be true. Reaching the tool is not enough — it throws
            // instead of confirming when `confirm` is not `true`, which is
            // exactly the mis-call this scenario provokes.
            groundedIn: IntegrationScenarioGrounding.booking
        )
    }
}
