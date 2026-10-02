import Testing

@testable import FoundationModelsMultitool
import ScenarioGrading

/// The prompt of the discovery scenario.
///
/// It asks two things, because card `^3vtvrzg` merged two scenarios into
/// this one: which trip city is warmest (the compose/chain and discovery
/// question), and how warm it is (the single-call question, which graded a
/// `getWeather` reading in the reply). "One short sentence" keeps the answer
/// as long as the check needs and no longer: each generated token costs
/// approximately 0.2 s on the CI runner `mini`, and the long replies of CI
/// run `36951032341` listed every city of the trip.
private let discoveryPrompt =
    "Of the cities on my trip, which is warmest right now, and how warm is it there? "
    + "Answer in one short sentence."

/// The gated real-model suite: the sample MultiTools scenarios, retargeted at
/// the shipped host contract — the tools
/// `MultiTool.Registry.makeSessionTools(selection:embedder:sampleSession:)` vends, mounted on a
/// `RoutedSession` and driven by draining `streamEvents(to:)` — "this is where
/// the plan's empirical search-then-call behavior is proven against real
/// hardware."
///
/// **Two scenarios, not four.** Card `^3vtvrzg` removed two duplicates. The
/// compose/chain scenario asked the discovery scenario's question over the
/// same two tools and graded the same answer and the same grounding; the
/// discovery scenario adds the ten distractors, so it proves all of that and
/// more. The single-call scenario graded one thing the discovery scenario did
/// not: that the reply states the reading `getWeather` returned. The
/// discovery scenario now asks for that reading too, and grades it
/// (`readingReported`). Its grounding already required the `getWeather`
/// return. The same card removed `AsyncFanOutTests` for the same reason: it
/// graded an answer that only the returns of two tools could give, grounded
/// in both, and its documentation stated that the route (`Promise.all` or two
/// awaits) was not asserted. The discovery scenario grades the same kind of
/// answer, grounded in the trip and the weather returns, and its natural
/// snippet awaits one `getWeather` call for each trip city at once.
///
/// **Outcome over path.** Each scenario passes when the model produces a
/// valid, grounded answer — see `runNativeIntegrationScenario`'s
/// documentation for the exact assertions and why route assertions
/// (tool ordering, exact call sets, call budgets) were retired in favor of
/// diagnostics. The `answerContainsOneOf` values below are the fixtures'
/// own distinctive data (`ScenarioGrading`'s `ScenarioTools.swift`), read from those
/// fixtures rather than restated here: `IntegrationScenarioAnswers` derives
/// both the one warmest trip city and its reading from
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
/// This suite lives in the nested `IntegrationTests` package, and the root
/// manifest declares no target for it, so the root `swift test` never sees it —
/// zero downloads, zero live inference — and stays green on a network/GPU-less
/// box (the default posture of this environment). The command that runs this
/// suite is `swift test --package-path IntegrationTests --no-parallel`.
/// `.serialized` holds the scenarios to one at a time inside this suite,
/// which is what `liveProfileTurnstile` (`Support/LiveRouterFixture.swift`)
/// holds across suite boundaries: concurrent live scenarios come back fluent
/// but ungrounded, so one live scenario at a time is a correctness
/// requirement of this target. That is a rule of the target and not a limit of
/// `Router` — Router's residency is pooled and reference-counted, so it holds
/// more than one profile resident quite happily. Real weight loading is heavy
/// enough that one scenario at a time is the sane default anyway, even though
/// each test resolves its own fresh `Router`. The `.timeLimit` of this suite
/// is the shared hang guard, `IntegrationHangGuard.timeLimit`. It stops a test
/// that cannot end, and it does not check the speed of the machine.
@Suite(
    "Gated search-then-call scenarios (M6.5a)",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct SearchThenCallTests {
    // MARK: - Discovery under distractors, with the compose walk and the reading

    @Test("discovery scenario names the warmest trip city and its reading among the distractor tools")
    func discoveryUnderDistractors() async throws {
        try await runNativeIntegrationScenario(
            name: "discoveryUnderDistractors",
            tools: { log in
                [IntegrationWeatherTool(log: log), IntegrationTripTool(log: log)]
                    + integrationDistractorTools(log: log)
            },
            prompt: discoveryPrompt,
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // The fixture's own reading for the warmest city — the check the
            // single-call scenario made. A value no hallucinated forecast has
            // ever produced (72°F, 25°C, 22°C were the observed inventions).
            readingContainsOneOf: IntegrationScenarioAnswers.warmestCityReading,
            // The itinerary *and* a reading: which cities are candidates comes
            // from one, which of them is warmest and how warm from the other.
            // A trip-only run that names a city is guessing. This is the
            // scenario whose recorded run named the warmest city off the
            // itinerary alone (task `0981ar3`).
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }

    // MARK: - Repair from a trip-prone tool

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
