import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The gated proof that `respond(to:)` self-drains its own background runs
/// (task `^n6kgckr`).
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
/// **Router's half landed** (`d2be019`, their `^nmpejc5`): `respond` snapshots
/// every run still going, settles them, and runs a continuation turn carrying
/// the results, bounded at four continuation turns.
///
/// **What this suite proves, and what it does not.** It proves the blocking
/// surface reaches the same grounded answer the streaming surface does, with no
/// background run left on return. It does **not** isolate Router's drain: the
/// model collects its own backgrounded runs in-band, because the pending
/// envelope instructs it to, so the drain has nothing left to settle. Measured
/// on real hardware, `waitCalls` is 1-2 per run and `backgroundRuns` is 0
/// either way.
///
/// **No suite in this target isolates the drain, and none can.** Isolating it
/// needs a turn that ends with a run still going, and Router's `^466d38p`
/// (their commit `b4c0282`) says no host can produce one: every background run
/// hands the model a `PendingRunEnvelope` telling it to collect that run with a
/// `wait` call first, and there is no background run without that instruction.
/// The suite written to try — task `^xeqs138` — measured the opposite on real
/// hardware and was inverted into `InBandCollectionCanaryTests`, which now
/// watches for the condition becoming reachable. Cite nothing here for "the
/// drain works".
///
/// Packaged like every other suite here: it belongs to the nested
/// `IntegrationTests` package, for which the root manifest declares no target,
/// so an ordinary `swift test` cannot reach it and stays green with zero
/// downloads and zero live inference. Run it with
/// `swift test --package-path IntegrationTests --no-parallel`.
@Suite(
    "Gated respond self-drain (phase-1 exit)",
    .serialized,
    .timeLimit(.minutes(30))
)
struct RespondDrainTests {
    @Test("respond answers from what the backgrounded run returned, matches the stream, and leaves nothing running")
    func respondSelfDrainsItsBackgroundRuns() async throws {
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
