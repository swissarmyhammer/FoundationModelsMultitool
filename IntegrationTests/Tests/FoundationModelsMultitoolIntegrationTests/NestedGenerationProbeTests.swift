import Testing

/// The gated probe that holds Router to completing a nested generation on the
/// model that the outer answer runs on.
///
/// **The contract.** `searchTools` generates from inside a tool call of the
/// outer answer. When one model serves the outer answer and the nested call,
/// the nested call needs the model of the outer answer. Since Router
/// `505a03f3` the one lock is MLX's FIFO lock in Extras `PooledGeneration`,
/// and it is held over the call into the model only, never over a tool call.
/// The SDK runs a tool body after the model's `respond` returns, so the nested
/// call takes the lock in its turn and completes. This probe makes that nested
/// call from inside a tool call and passes only when it comes back with a
/// reply.
///
/// **What it replaced.** Before the work-queue Router, the same nested call
/// hung for ever: the old `RoutedModel.generationGate` was an
/// `AsyncSemaphore(value: 1)` that `beginTurn()` held across the tool rounds
/// of an answer, so the nested `respond` parked on `generationGate.wait()` and
/// never came back. Measured on 2026-08-16 it parked 165.4s and 166.5s and
/// unwound only when the test run cancelled the outer answer. The work-queue
/// Router then refused the call at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`, and this probe
/// held that refusal until the user's rule of 2026-10-24: locks must not cross
/// over a tool call, only over the actual call into the model.
///
/// **No grammar anywhere.** The one tool mounted opens a plain
/// `makeSession()` in its body: no guided session, no selection tier, no
/// `MetadataSearcher`, and no `searchTools`. The question is the lock, so
/// nothing else may be in the run.
///
/// **How to read a run.**
///
/// - `nestedGenerationReturned` holds: the nested call completed, which is
///   the contract.
/// - `nestedGenerationReturned` fails with "an error": the nested call threw.
///   The message names the error.
/// - The run does not end: the nested call hung. A lock crosses a tool call
///   again. The swift-log output of the run shows the enter record
///   `enter FoundationModelsMultitoolIntegrationTests.nestedRespond`, with no
///   ended span for that call.
///
/// **This suite grades plumbing, not capability, and that is why it resolves a
/// small model.** Every assertion here is about how a nested call on the
/// outer answer's model ends. Nothing is asserted about the quality, the
/// grounding or even the content of what the model says — the reply is
/// printed and graded by nothing. So the model's whole job is to emit tokens
/// and call the one tool mounted, which any tool-calling model does. It
/// therefore resolves `plumbingProbeProfile`; `plumbingProbeModel` carries the
/// rule and names the suites that must **not** follow it.
///
/// Like every suite here it lives in the nested `IntegrationTests` package,
/// which the root manifest declares no target for, so the root `swift test`
/// never sees it and stays green with zero downloads and zero live inference;
/// `swift test --package-path IntegrationTests --no-parallel` is what runs it.
/// The grading rule itself is covered without a live model, on each outcome,
/// in `ScenarioGradingTests`.
@Suite(
    "Gated nested-generation probe (a nested generation on the outer answer's model completes)",
    .serialized
    // No test checks the speed of the machine (card `^tm4x2hp`). A hang does
    // not return, thus no grade reports it.
)
struct NestedGenerationProbeTests {
    @Test("a tool body generating on the outer answer's own model gets a reply")
    func aNestedGenerationOnTheOuterAnswersModelCompletes() async throws {
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
