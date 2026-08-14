import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The gated proof that `respond(to:)` self-drains the run plane (task
/// `^n6kgckr`).
///
/// **Why this suite exists beside the streaming ones, never in place of them.**
/// `respond` drains, so a suite that drifted onto it would stop observing the
/// three rules entirely: a backgrounded `runCode` is collected before the
/// caller sees it, a `wait` has nothing left to wait for, and a blocking
/// `searchTools` is indistinguishable from a detaching one. The scenarios in
/// `SearchThenCallTests` and `ElevationTests` stay on streaming for exactly
/// that reason. This suite adds the one job `respond` keeps: proving that the
/// blocking surface still reaches the same grounded answer once every tool
/// call hands back a token instead of data.
///
/// **This suite is written to fail while Router's half is missing.** Router's
/// `respond(to:maxTokens:)` awaits generation only — its own comment says it
/// composes the prompt with "whatever the outbox drains for this turn", and
/// the outbox is not the run plane; `sweep()` is teardown that cancels parked
/// runs rather than settling them. Filed as `^nmpejc5` on Router's board. Until
/// that lands, a red run here is the requirement being observed, not a flake:
/// expect a dangling parked run, and an answer written from a token.
///
/// `.enabled(if: multitoolIntegrationEnabled)` like every other gated suite —
/// with `MULTITOOL_INTEGRATION` unset the whole thing is skipped, so ungated
/// `swift test` stays green with zero downloads and zero live inference.
@Suite(
    "Gated respond self-drain (phase-1 exit)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct RespondDrainTests {
    @Test("respond answers from what the backgrounded run returned, leaves nothing parked, and needs no wait call")
    func respondSelfDrainsTheRunPlane() async throws {
        try await runRespondDrainScenario(
            name: "respondSelfDrain",
            // The compose/chain pair, deliberately: the answer needs two tools,
            // so a run that drained only the first is visible as a wrong answer
            // rather than a lucky one.
            tools: { log in [IntegrationTripTool(log: log), IntegrationWeatherTool(log: log)] },
            prompt: "Of the cities on my trip, which is warmest right now?",
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // The itinerary says which cities are candidates; a reading says
            // which of them is warmest. A trip-only run that names a city is
            // guessing, on this surface exactly as on the streaming one.
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }
}
