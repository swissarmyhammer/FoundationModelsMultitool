import Testing

/// The gated proof that Router's parked-run drain is what collects a run the
/// turn left in flight (task `^xeqs138`).
///
/// **Why this suite exists beside `RespondDrainTests`, and not inside it.** That
/// suite asserts `parked == 0` when `respond(to:)` returns, which is necessary
/// and not sufficient: two different mechanisms empty the run plane, and only
/// one of them is the drain. Measured on real hardware the *other* one runs —
/// the model collects its own backgrounded run in band with a `wait` call,
/// because the pending envelope tells it to
/// (`PendingRunEnvelope.renderedMidfix`) — so `waitCalls` was 1 and 2 across two
/// recorded runs with `parked` at 0 both times. The drain was never entered.
/// Its whole-plane snapshot, its bounded re-entry at
/// `RoutedSessionActor.parkedRunDrainRoundLimit` continuation turns, and its
/// rule that a run parked from inside a drained turn is drained too had never
/// executed in any scenario this target ships.
///
/// That is a live regression hole, not a tidiness point: if the drain broke
/// tomorrow, every existing gated scenario would still pass, because the model's
/// own `wait` calls would keep the run plane clean.
///
/// **What this suite asserts that no other one can.** The scenario's fixture is
/// held open until this runner sees the model's first turn end, so the turn
/// genuinely ends with the run parked; and the model makes no `wait` call, so
/// nothing but the drain can have collected it. The reply then carries the
/// rebuild's own manifest code — a value that reaches the model only through a
/// collected terminal event. See `runParkedRunDrainScenario` for why those two
/// facts together are a complete proof, and for the two product rules
/// (`runCode` always parks; `wait` is the only in-band collector) they rest on.
///
/// **What it still does not prove.** It exercises exactly one drain round. The
/// re-entry bound is the rule that stops a model chaining background work from
/// spinning forever, and a scenario that starts new work from *inside* a drained
/// turn is what would exercise it. Nobody should cite this suite as proof of
/// that bound.
///
/// `.enabled(if: multitoolIntegrationEnabled)` like every other gated suite —
/// with `MULTITOOL_INTEGRATION` unset the whole thing is skipped, so ungated
/// `swift test` stays green with zero downloads and zero live inference.
@Suite(
    "Gated parked-run drain (turn ends with work in flight)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct ParkedRunDrainTests {
    @Test("the drain collects a run the turn left in flight, and the answer comes from what it returned")
    func drainCollectsARunLeftInFlight() async throws {
        try await runParkedRunDrainScenario(
            name: "parkedRunDrain",
            tools: { log, gate in [IntegrationArchiveRebuildTool(log: log, gate: gate)] },
            // Asks for the manifest code, so the answer needs the run's result;
            // and says plainly not to block for it, so the model has no reason to
            // spend a `wait` call. Both halves are load-bearing. Dropping the
            // first leaves nothing for the drained turn to answer with; dropping
            // the second invites the `wait` the recorded `RespondDrainTests` runs
            // measured, and a run that waits proves nothing about the drain.
            //
            // Phrased as a user request rather than as coaching: "start it, tell
            // me when it is running, give me the code when it lands" is how
            // someone asks for work they do not want to sit through, and the
            // whole point of the drain is that such a caller still gets the
            // answer without ever making the model block for it.
            prompt: "Rebuild my archive index and tell me its exact manifest code. Do not block "
                + "waiting for it: start the rebuild, reply as soon as it is under way, and give me "
                + "the manifest code once it reaches you.",
            // The rebuild fixture always reports the same manifest code, and it
            // reaches the model only through the collected run's terminal
            // `detail` — a hallucinated answer cannot match it.
            answerContainsOneOf: integerAnswers(for: integrationArchiveRebuildManifestCode),
            groundedIn: IntegrationScenarioGrounding.archiveRebuild
        )
    }
}
