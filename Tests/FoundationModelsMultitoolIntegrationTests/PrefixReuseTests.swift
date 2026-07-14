import Foundation
import Testing

import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// The gated selection-tier prefix-reuse pin (plan.md Finding #6 /
/// "Remaining pins"): asserts `findAPIsTool`'s own internal selection tier's
/// *second* `findAPIs` call does not re-prefill the surface prefix —
/// compared via prefill latency evidence — or documents that the `fork()`
/// fallback is the mechanism actually engaged.
///
/// The registry's `SelectionTier` (generalizing Multitool's former
/// `Librarian`) is architected to `fork()` a fresh child from one cached,
/// prefix-rooted root session per selection call, specifically so the
/// surface prefix is prefilled once rather than replayed on every call
/// (`RoutedSession.fork(workingDirectory:)` seeds the child from a *copy* of
/// the parent's prefilled KV cache). This suite is the empirical check of
/// that design against real hardware: on a machine where `fork()`-based
/// reuse genuinely avoids re-prefilling, the second call's wall-clock
/// latency should be no slower than the first (which pays the cold prefill
/// of the whole rendered surface); every selection call still goes through
/// exactly one `fork()`, so the mechanism-under-test is asserted, not merely
/// observed, by construction.
///
/// **Native design, minimal change.** This scenario is about `findAPIsTool`'s
/// own internal selection tier — a plain, Router-backed `RoutedLLM` session
/// (task `4aveepp`'s decision, kept specifically to preserve this property)
/// — not about `MultiToolAgent`'s retired ReAct loop, so it ports with
/// minimal change: rather than driving a raw `MetadataSearcher` built via the
/// retired `MultiToolAgent.makeFindAPISearcher(registry:librarian:)`, it now
/// times `FindAPIsTool.call(arguments:)` directly — `findAPIsTool`'s own
/// production, independently-constructible entry point (`FindAPIsTool
/// .init(registry:librarian:limit:)`) — which forwards to the identical
/// `.auto`-mode `MetadataSearcher`/`SelectionConfig`/`fork()` mechanism the
/// old test exercised through the searcher directly, just reached through
/// the real `Tool` surface instead of a production-only factory method.
///
/// Gated the same way as `SearchThenCallTests`: `.enabled(if:
/// multitoolIntegrationEnabled)`, skipping cleanly (no recorded issue) when
/// the live Router path throws `GenerationError.notWiredForLiveInference`.
@Suite(
    "Selection tier prefix-reuse pin (M6.5a)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct PrefixReuseTests {
    @Test(
        "a selection tier's second findAPIs call is no slower than its first (fork()-inherited prefix, not re-prefilled)"
    )
    func secondSearchCallReusesThePrefix() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [prefixReuse]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            // A surface large enough that a full re-prefill would be
            // measurably slower than a `fork()`-inherited one — the same
            // ~20-tool set `SearchThenCallTests`' discovery scenario uses.
            let registry = try MultiTool.Builder()
                .addTools([IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools)
                .buildRegistry()
            // `findAPIsTool`'s own production initializer — never a
            // reimplementation of its selection-tier wiring.
            let findAPIsTool = try FindAPIsTool(registry: registry, librarian: fixture.profile.flash)

            let firstStart = Date()
            _ = try await findAPIsTool.call(
                arguments: FindAPIsArguments(task: "list trip cities and get weather for each")
            )
            let firstElapsed = Date().timeIntervalSince(firstStart)

            let secondStart = Date()
            _ = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "convert 100 USD to EUR"))
            let secondElapsed = Date().timeIntervalSince(secondStart)

            // Prefix-reuse pin acceptance: "the second findAPIs call shows
            // no full re-prefill... an assertion, not an observation." A
            // cold first call pays the whole surface's prefill; a
            // `fork()`-inherited second call should not pay it again, so it
            // should be no slower.
            #expect(
                secondElapsed <= firstElapsed,
                """
                expected the second findAPIs call (fork()-inherited prefix) to be no slower than the first \
                (cold prefill): first=\(firstElapsed)s second=\(secondElapsed)s — if this fails on real \
                hardware, it means fork()-based prefix reuse is NOT avoiding a full re-prefill here, and \
                the plan's Finding #6 pin should be recorded as unresolved rather than confirmed
                """
            )
            print("RESULT [prefixReuse] first=\(firstElapsed)s second=\(secondElapsed)s")

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [prefixReuse]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }
}
