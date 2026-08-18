import Foundation
import Testing

import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// How many `searchTools` calls the scenario makes, and therefore how many
/// `fork()`s of the selection tier's cached root it must produce.
private let selectionCallCount = 2

/// The gated selection-tier `fork()`-per-call trace.
///
/// ## What this suite establishes
///
/// `searchToolsTool`'s own internal selection tier keeps ONE cached,
/// prefix-rooted root session and forks a fresh child from it for every
/// selection call — `SelectionTier.search` does `cachedRootSession().fork()`
/// and then `child.respond(to:generating:)`. Those children are Router-vended
/// and therefore recorded, so the recording names them. This suite runs two
/// `searchTools` calls over a ~20-tool surface, reads the `.flash` slot's own
/// events back, and holds the run to that contract: every selection
/// generation ran on a forked child, each call forked a child of its own, and
/// every child came off the same single root. The mechanism is asserted from
/// the recording rather than assumed.
///
/// It also times the two calls and holds the second to being no slower than
/// the first. That is a timing observation and nothing more — see below.
///
/// ## What this suite CANNOT establish, and why it was renamed
///
/// It was `PrefixReuseTests`, and its suite name called it a pin. It pinned
/// nothing. Its one assertion was `secondElapsed <= firstElapsed`, and the
/// first call pays a model warm-up the second never pays, so a run that
/// re-prefilled the whole surface from scratch satisfies it exactly as well
/// as a run that skipped a prefill. Measured 2026-08-16, both candidate
/// models pass and neither passes decisively — Muse Glimmer `first=7.75s
/// second=3.31s`, Qwen3.8 `first=5.81s second=3.58s`. The assertion is kept
/// because "the second call is not slower" is true and worth holding; it is
/// not evidence of prefix reuse, and no reader should take it for any.
///
/// The recorded entries cannot rescue it either. That was checked against the
/// shipped build before this suite was narrowed, rather than assumed:
///
/// - `TranscriptEvent` meters `tokensIn`, `tokensOut` and `ms`, and nothing
///   else. It carries no skipped-token count, no cache-hit count and no
///   prefill time.
/// - `tokensIn` is the whole rendered prompt of the turn. Router stamps it
///   as the delta of two `LanguageModelSessionBackend.usageTokenCounts()`
///   snapshots. Those snapshots are cumulative over the session, so the
///   delta is that turn's own whole render only because every fork here is
///   a fresh session that starts at zero. What the snapshots read is
///   `usage.input.totalTokenCount`, and that total counts the render
///   whether or not a cached prefix was skipped.
/// - The one figure that would answer the question,
///   `usage.input.cachedTokenCount`, never arrives here. Router's live
///   conformer, `MLXFoundationModelsSessionBackend.usageTokenCounts()`,
///   reads only the two `totalTokenCount`s and drops it; and in the pinned
///   `mlx-swift-lm` the FoundationModels executor carries no prompt cache
///   at all, so `cachedTokenCount` is the literal `0` at every emission
///   site. On this build nothing is ever skipped, so there is nothing for
///   a count to report.
///
/// A live run bears that out and then goes one worse. Both selection turns
/// recorded exactly `tokensIn=1144`, although their two intents tokenize two
/// tokens apart under the model's own tokenizer — so the number does not even
/// move with the prompt, and no source in `FoundationModelsRouter` or
/// `mlx-swift-lm` explains why. It is printed below as a diagnostic and
/// asserted on by nothing.
///
/// The `fork()` itself does not carry a prefilled cache on this path either:
/// `MLXFoundationModelsSessionBackend.makeFork(tools:)` builds a brand-new
/// `LanguageModelSession` seeded from the parent's *transcript*. What the
/// child inherits is history, not a KV cache.
///
/// ## Where the rigorous measurement lives
///
/// Not here. `mlx-swift-lm`'s `f85fc50` measures two-round reuse on real
/// weights through `MLXLMCommon.ChatSession`, comparing rendered token counts
/// and prefill time against a cold control. Its verdict on Qwen3.6 was NO on
/// two independent counts: round 2's render was not a prefix extension of
/// round 1's — the two shared 4,703 of 4,705 tokens and still did not extend,
/// because round 1 ends with a `<think>` priming block exactly where round 2
/// writes the assistant reply — and round 2 fed all 4,748 rendered tokens,
/// skipped none, and spent 11.59s on prefill against a cold control's 11.60s.
/// Read that suite for whether prefix reuse works. Never cite this one.
///
/// ## Why the suite stays
///
/// The `fork()`-per-call path is real, it is what every `searchTools` call in
/// this target takes, and nothing else in the target exercises it twice in a
/// row off one cached root. That is worth holding whatever becomes of the
/// reuse claim.
///
/// Gated the same way as `SearchThenCallTests`: `.enabled(if:
/// multitoolIntegrationEnabled)`, skipping cleanly (no recorded issue) when
/// the live Router path throws `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated selection tier fork()-per-call trace (prefix reuse itself unmeasured)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct SelectionForkPerCallTests {
    @Test(
        "two consecutive searchTools selections each fork their own child off the tier's one cached root"
    )
    func eachSelectionCallForksItsOwnChild() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [selectionFork]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            // A surface large enough to be worth prefilling once — the same
            // ~20-tool set `SearchThenCallTests`' discovery scenario uses.
            // This measurement never calls a fixture tool — it runs two
            // `searchTools` selections over the rendered surface — but every
            // fixture still needs a log to construct, so it gets one that
            // stays empty.
            let log = ScenarioCallLog()
            let registry = try MultiTool.Builder()
                .addTools(
                    [IntegrationWeatherTool(log: log), IntegrationTripTool(log: log)]
                        + integrationDistractorTools(log: log)
                )
                .buildRegistry()
            // `searchToolsTool`'s own production initializer — never a
            // reimplementation of its selection-tier wiring.
            let searchToolsTool = try SearchToolsTool(registry: registry, librarian: fixture.profile.flash)

            let firstStart = Date()
            _ = try await searchToolsTool.call(
                arguments: SearchToolsArguments(task: "list trip cities and get weather for each")
            )
            let firstElapsed = Date().timeIntervalSince(firstStart)

            let secondStart = Date()
            _ = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "convert 100 USD to EUR"))
            let secondElapsed = Date().timeIntervalSince(secondStart)

            let trace = SelectionForkTrace(events: try fixture.transcriptEvents())
            expectForkPerCall(trace)
            expectSecondCallNoSlower(first: firstElapsed, second: secondElapsed)
            reportDiagnostics(trace, first: firstElapsed, second: secondElapsed)

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [selectionFork]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }
}

/// The selection tier's own `fork()` trace, read out of one gated run's
/// recorded transcript.
///
/// Every selection call reaches the model through a Router-vended session, so
/// the recording holds one `.response`-kind event per selection generation,
/// stamped with the session that generated it and the session that forked it.
/// This is that projection, and nothing else.
private struct SelectionForkTrace {
    /// Every recorded selection generation, in recorded order.
    let generations: [TranscriptEvent]

    /// The distinct sessions those generations ran on — one per `fork()`.
    let childSessionIds: Set<ULID>

    /// The distinct sessions those children were forked from.
    let rootSessionIds: Set<ULID>

    /// How many generations name no forking parent at all — a session the
    /// tier reached without forking, which its cached-root contract forbids.
    let unforkedGenerationCount: Int

    /// Projects one gated run's recorded events onto the selection tier.
    ///
    /// - Parameter events: the run's whole recorded event stream, as
    ///   `LiveRouterFixture.transcriptEvents()` returns it.
    init(events: [TranscriptEvent]) {
        generations = events.filter { $0.slot == .flash && $0.kind == .response }
        childSessionIds = Set(generations.map(\.sessionId))
        rootSessionIds = Set(generations.compactMap(\.parentId))
        unforkedGenerationCount = generations.count { $0.parentId == nil }
    }
}

/// Holds a run to the selection tier's cached-root, `fork()`-per-call contract.
///
/// - Parameter trace: the run's own recorded selection trace.
private func expectForkPerCall(_ trace: SelectionForkTrace) {
    #expect(
        trace.generations.count >= selectionCallCount,
        """
        expected at least \(selectionCallCount) recorded selection generations, one per searchTools call, \
        but the .flash slot recorded \(trace.generations.count) — the selection tier did not reach the \
        model once per call
        """
    )
    #expect(
        trace.childSessionIds.count >= selectionCallCount,
        """
        expected each searchTools call to fork a child session of its own, so at least \
        \(selectionCallCount) distinct selection sessions, but the run recorded \
        \(trace.childSessionIds.count) — the second call did not fork, it reused the first call's child
        """
    )
    #expect(
        trace.unforkedGenerationCount == 0,
        """
        expected every selection generation to name the root it was forked from, but \
        \(trace.unforkedGenerationCount) of \(trace.generations.count) name no parent at all — that \
        generation reached the model without a fork, which the tier's cached-root contract forbids
        """
    )
    #expect(
        trace.rootSessionIds.count == 1,
        """
        expected every selection child to be forked from the tier's ONE cached root, but the run \
        recorded \(trace.rootSessionIds.count) distinct roots — the cached root was dropped and \
        rebuilt between calls, so each call re-assembled the surface prefix from scratch
        """
    )
}

/// Holds the second selection call to being no slower than the first.
///
/// A timing comparison and nothing more. The first call pays model warm-up
/// the second never pays, so this holds on a run that re-prefills the whole
/// surface exactly as it holds on one that skips a prefill — see this file's
/// suite documentation, and never read a pass here as prefix reuse.
///
/// - Parameters:
///   - first: the first `searchTools` call's wall-clock duration.
///   - second: the second call's wall-clock duration.
private func expectSecondCallNoSlower(first: TimeInterval, second: TimeInterval) {
    #expect(
        second <= first,
        """
        expected the second searchTools call to be no slower than the first, which pays the cold \
        model warm-up: first=\(first)s second=\(second)s. This is a warm-vs-cold timing check, not a \
        prefix-reuse check — a failure means the second call got slower than a COLD first call, which \
        no warm path should manage
        """
    )
}

/// Prints what the run measured, including the numbers nothing asserts on.
///
/// `tokensIn` is here as a diagnostic only. It is the whole rendered prompt of
/// the turn, so it reads the same whether a prefix was reused or re-prefilled,
/// and on this build it has been observed not to move with the prompt at all.
///
/// - Parameters:
///   - trace: the run's own recorded selection trace.
///   - first: the first `searchTools` call's wall-clock duration.
///   - second: the second call's wall-clock duration.
private func reportDiagnostics(_ trace: SelectionForkTrace, first: TimeInterval, second: TimeInterval) {
    print(
        "RESULT [selectionFork] first=\(first)s second=\(second)s "
            + "children=\(trace.childSessionIds.count) roots=\(trace.rootSessionIds.count)"
    )
    for generation in trace.generations {
        print(
            "RESULT [selectionFork] generation seq=\(generation.seq) "
                + "tokensIn=\(String(describing: generation.tokensIn))(asserted on by nothing) "
                + "tokensOut=\(String(describing: generation.tokensOut)) "
                + "ms=\(String(describing: generation.ms))"
        )
    }
}
