import Testing

/// The gated probe that names the layer a nested generation deadlocks in.
///
/// **The observation.** A gated scenario hangs for ever — 0% CPU, ~19GB
/// resident, 98% of system memory free, zero swap, every thread parked and the
/// MLX scheduler on a condition variable — when both slots of
/// `multitoolTinyProfile` name one `ModelRef`, because `searchTools` generates
/// from inside the outer turn's tool call. `TinyModels` records the measurement
/// and records that splitting the two pins removes it; what it does not record
/// is *why*, and it says so.
///
/// **The two explanations, and why one run separates them.**
///
/// - MLX's guided path deadlocks: the selection tier runs under a grammar, and
///   xgrammar keeps shared per-model caches, so a nested grammar-constrained
///   decode on a container already generating is the hazard.
/// - Router's `RoutedModel.generationGate` deadlocks: it is an
///   `AsyncSemaphore(value: 1)` minted once per resident container, `beginTurn()`
///   takes a permit and `endTurn()` is what hands it back, so a turn holds it
///   across its tool rounds. A nested `respond` on that same container parks on
///   `generationGate.wait()` and can never be admitted — the permit it waits for
///   is freed by the turn's end, the turn's end waits on the tool call, and the
///   tool call waits on it. `AsyncSemaphore.wait()` is a bare
///   `withCheckedContinuation` with no cancellation handler, which is exactly why
///   the observed hang is silent, burns no CPU, and cannot be killed.
///
/// The first explanation requires a grammar. The second requires none. So this
/// suite runs the same shape with **no grammar anywhere** — a plain
/// `makeSession()` inside the tool body, no guided session, no selection tier,
/// no `MetadataSearcher` — and mounts one tool, never `searchTools`.
///
/// **How to read a run.**
///
/// - It hangs: Router's gate is the fault and MLX is exonerated. The `GATE`
///   lines say so directly — zero permits, one waiter — and `log show
///   --predicate 'subsystem == "com.swissarmyhammer.multitool" AND category ==
///   "NestedGenerationProbe"'` shows `enter nestedRespond` with no matching
///   `exit`.
/// - It completes: the grammar is what matters, and the MLX explanation stands.
///
/// **It hung.** Measured 2026-08-16, both slots pinned to
/// `mlx-community/Muse-Glimmer-30B-4bit`: the gate went `permits=1 waiters=0`,
/// then `permits=0 waiters=0` as `beginTurn()` took the permit, then
/// `permits=0 waiters=1` and stayed there for the rest of the run; the span
/// opened at 08:15:49.698 and closed at 08:18:34.135 with a `CancellationError`
/// — 165 seconds parked, unwound only because the time limit cancelled the
/// outer turn and `endTurn()` handed the permit back. No grammar was in the run
/// at all. `runNestedGenerationProbe` records the whole reading. So the second
/// explanation above is the fault, the first is not needed to account for the
/// hang, and the fix belongs to Router rather than to MLX or xgrammar.
///
/// **Why it stays now the question is answered.** This is the regression test
/// for the layer it named: whatever admits a nested generation on a held
/// container has to keep admitting it, and a change that puts the deadlock back
/// fails here, in three minutes, with a reading rather than a mystery. It
/// **fails today**, and that is honest — it will pass when the gate is fixed.
///
/// `.enabled(if: multitoolIntegrationEnabled)` like every other gated suite —
/// with `MULTITOOL_INTEGRATION` unset the whole thing is skipped, so ungated
/// `swift test` stays green with zero downloads and zero live inference. The
/// grading rule itself is covered ungated, on both readings, in
/// `ScenarioGradingTests`.
@Suite(
    "Gated nested-generation probe (an unguided generation inside a tool call)",
    .serialized,
    // Three minutes, the in-band collection canary's limit and for its reason:
    // this is one tool call plus one short nested turn, so a live run belongs
    // in the same 40-90 second band its peers finish in. The failure this suite
    // exists to catch is a deadlock, and a deadlock is reported by the limit
    // being reached — so the limit has to sit near the expected runtime. A
    // generous ceiling would turn a two-minute answer into a half-hour wait
    // that graded nothing, which is what it already cost that canary once.
    .timeLimit(.minutes(3)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct NestedGenerationProbeTests {
    @Test("a tool body generating on the outer turn's own model, with no grammar anywhere, comes back")
    func anUngrammaredNestedGenerationComesBack() async throws {
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
