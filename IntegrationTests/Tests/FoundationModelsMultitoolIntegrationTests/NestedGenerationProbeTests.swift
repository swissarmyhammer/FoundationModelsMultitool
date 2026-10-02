import Testing

/// The gated probe that holds Router to refusing a nested generation on the
/// model that the outer turn holds open.
///
/// **The contract.** `searchTools` generates from inside the outer turn's
/// tool call. When one model serves the outer turn and the nested call, the
/// nested call needs a model that the outer submission holds open. The
/// work-queue Router refuses that nested call at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`: its queue sees
/// the open submission of the same model and throws before it queues
/// anything. This probe makes that nested call from inside a tool call and
/// passes only when the nested call gets the refusal at once: the queue of
/// the model, read at the refusal, shows the outer submission still running
/// and no job waiting behind it. The order of events decides, and no
/// real-time bound (card `^kdtrmhv`: no test checks the speed of the machine).
///
/// **What it replaced.** Before the work-queue Router, the same nested call
/// hung for ever: the old `RoutedModel.generationGate` was an
/// `AsyncSemaphore(value: 1)` that `beginTurn()` held across the tool rounds
/// of a turn, so the nested `respond` parked on `generationGate.wait()` and
/// never came back. Measured on 2026-08-16 it parked 165.4s and 166.5s and
/// unwound only when the hang guard of this suite cancelled the outer turn.
/// Router's `^1zt7vyg` then lent the permit to the nested turn, and the call
/// came back. The work-queue Router replaced both with the refusal. The
/// profiles of this target therefore put a different model in `standard` and
/// `flash` (`LiveRouterFixture`), and `ProfileSlotSeparationTests` holds that.
///
/// **No grammar anywhere.** The one tool mounted opens a plain
/// `makeSession()` in its body: no guided session, no selection tier, no
/// `MetadataSearcher`, and no `searchTools`. The refusal is a property of the
/// queue, so nothing else may be in the run.
///
/// **How to read a run.**
///
/// - `nestedGenerationRefused` and `nestedRefusalAtOnce` hold: Router refused
///   the nested call at once, which is the contract.
/// - `nestedRefusalAtOnce` fails alone: Router refused, but not at once. The
///   message names the queue reading at the refusal: a job waited behind the
///   outer submission, or no job ran because the outer submission had closed.
/// - `nestedGenerationRefused` fails with "a reply": Router let the nested
///   call through. The refusal is gone.
/// - `nestedGenerationRefused` fails with "a different error": the nested
///   call threw something else. The message names the error.
/// - The hang guard of this suite ends the run: the nested call hung, which
///   is the old defect. The `QUEUE` lines show the queue state for the whole
///   run, and the swift-log output of the run shows the enter record
///   `enter FoundationModelsMultitoolIntegrationTests.nestedRespond`, with no
///   ended span for that call.
///
/// **This suite grades plumbing, not capability, and that is why it resolves a
/// small model.** Every assertion here is about how a nested call on a held
/// model ends. Nothing is asserted about the quality, the grounding or even
/// the content of what the model says — the reply is printed and graded by
/// nothing. So the model's whole job is to emit tokens and call the one tool
/// mounted, which any tool-calling model does. It therefore resolves
/// `plumbingProbeProfile`; `plumbingProbeModel` carries the rule and names the
/// suites that must **not** follow it.
///
/// Like every suite here it lives in the nested `IntegrationTests` package,
/// which the root manifest declares no target for, so the root `swift test`
/// never sees it and stays green with zero downloads and zero live inference;
/// `swift test --package-path IntegrationTests --no-parallel` is what runs it.
/// The grading rule itself is covered without a live model, on each outcome,
/// in `ScenarioGradingTests`.
@Suite(
    "Gated nested-generation probe (a nested generation on the held model is refused)",
    .serialized,
    // The limit is the shared hang guard, `IntegrationHangGuard.timeLimit`.
    // It stops a test that cannot end. It does not check the speed of the
    // machine (card `^tm4x2hp`).
    //
    // A hang never returns to be graded, so the hang guard is what reports
    // it. The limit starts when the test starts, and not when generation
    // starts (`LiveRouterFixture`). The hang guard stands far above the
    // turnstile queue and the profile load.
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct NestedGenerationProbeTests {
    @Test("a tool body generating on the outer turn's own model gets waitInsideOpenSubmission at once")
    func aNestedGenerationOnTheHeldModelIsRefused() async throws {
        try await runNestedGenerationProbe(
            name: "nestedGeneration",
            // Phrased as a user request, not as coaching: one tool is mounted,
            // its description says what it does, and asking for the check is
            // how someone would ask for it. Nothing here tells the model how to
            // call anything — the tool's own description is the whole contract,
            // as it is in every other gated scenario.
            prompt: "Check that your language model is responsive right now, and tell me the "
                + "readiness token that check reports."
        )
    }
}
