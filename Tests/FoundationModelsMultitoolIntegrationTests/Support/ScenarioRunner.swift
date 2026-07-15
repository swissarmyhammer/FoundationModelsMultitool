import Foundation
import Testing

import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool
@testable import multitool_cli

/// Runs one gated scenario end to end against a freshly-resolved live
/// profile, using the *native* `LanguageModelSession`-driven design — no
/// `MultiToolAgent`, no `TurnFormat`, no hand-rolled turn parsing. Builds a
/// real `MLXLanguageModel` over the resolved `.standard` slot via
/// `CLIRunner.makeMLXLanguageModel(for:)` (the exact production wiring
/// `multitool-cli` itself uses — never a reimplementation of it), registers
/// `multiTool` and `findAPIsTool` (the latter backed by the resolved
/// `.flash` slot, mirroring the "librarian on flash" split) directly with a
/// `LanguageModelSession`, and lets Apple's own native tool-calling loop
/// decide when to call each.
///
/// **Outcome over path.** A scenario passes when the model produces a
/// *valid, grounded answer* — not when it takes the exact route we
/// predicted. Empirically (recorded on task `k4mj1gm`), asserting on the
/// route failed in both directions: a run once *passed* the compose
/// scenario while answering "there are no cities on your trip" (approved
/// path, wrong answer), and another *failed* it while answering "NYC, 31°C"
/// (correct grounded answer, unapproved path). So exactly three things are
/// asserted:
///
/// 1. **The answer is valid** — the reply contains at least one of
///    `answerContainsOneOf`, chosen per scenario to match the fixtures'
///    distinctive values (e.g. the weather fixture's constant 31°C, the
///    fixed trip-city list), so a hallucinated answer cannot match.
/// 2. **The answer is grounded** — at least one `runCode` snippet genuinely
///    invoked a `tools.*` function. Which functions, in what order, across
///    how many calls is deliberately unasserted.
/// 3. **Side effects really happened** — when `mustInvoke` is non-empty
///    (the booking scenario), those `tools.*` paths appear among the
///    invoked set: claiming "your booking is confirmed" without ever
///    calling `book` is a false claim, not a valid answer. This is a
///    containment check, never an equality — extra calls and any ordering
///    are fine.
///
/// The old route assertions (findAPIs-before-runCode ordering, exact
/// invoked-path sets, exact selection-tier picks, call-count budgets) are
/// printed as diagnostics on the `RESULT` line instead, so runs remain
/// comparable without gating on them.
///
/// **Skip, not failure.** Mirrors the retired `runIntegrationScenario` this
/// supersedes: if resolving the profile or running the session throws
/// `GenerationError.notWiredForLiveInference`, this prints a note and returns
/// *without recording any issue* — Swift Testing reports a test with no
/// recorded issues as passed, so the suite stays green rather than failing
/// when live inference isn't wired up in this environment. Any other error
/// propagates as an ordinary test failure — real signal once a caller has
/// opted in via `MULTITOOL_INTEGRATION` on capable hardware.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used only in the
///     printed result/skip line.
///   - tools: the scenario's fixed tool set.
///   - prompt: the user request driving `session.respond(to:)`.
///   - answerContainsOneOf: candidate substrings, at least one of which the
///     final reply must contain (case-insensitively) to count as a valid
///     answer. Pick values a hallucinating model cannot guess — the
///     fixtures' own distinctive data.
///   - answerMustNotContain: substrings whose (case-insensitive) presence
///     invalidates the answer even when a required substring matched —
///     guards required words that also appear inside failure phrasings
///     ("unable to confirm" contains "confirm"). Empty by default.
///   - mustInvoke: `tools.*` paths that must appear among the genuinely
///     invoked calls — for scenarios whose valid answer *claims a side
///     effect happened* (booking confirmed). Empty (the default) for pure
///     data-read scenarios, where the answer-content check already proves
///     grounding.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`
///   — including a failed `#expect` (Swift Testing turns a failed
///   expectation into a recorded issue, not a thrown error, so this
///   signature only actually throws for genuine setup/dispatch failures).
func runNativeIntegrationScenario(
    name: String,
    tools: [any Tool],
    prompt: String,
    answerContainsOneOf: [String],
    answerMustNotContain: [String] = [],
    mustInvoke: Set<String> = []
) async throws {
    let fixture: LiveRouterFixture
    do {
        fixture = try await LiveRouterFixture.resolve()
    } catch GenerationError.notWiredForLiveInference {
        print("SKIP [\(name)]: Router's live-inference path is not wired up in this environment.")
        return
    }

    do {
        let registry = try MultiTool.Builder().addTools(tools).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let findAPIsTool = try FindAPIsTool(registry: registry, librarian: fixture.profile.flash)
        let mlxModel = CLIRunner.makeMLXLanguageModel(for: fixture.profile.standard)
        let session = LanguageModelSession(
            model: mlxModel,
            tools: [multiTool, findAPIsTool],
            // The production instructions, shared verbatim (see its doc
            // comment) — the suite measures exactly what the CLI ships.
            instructions: CLIRunner.toolUseInstructions
        )

        let start = Date()
        // Explicitly typed to pin the native FoundationModels API over
        // `FoundationModelsRanker`'s shadowing `respond(to:) -> String`
        // `AgentSession` extension.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let transcript = session.transcript
        let invoked = NativeTranscript.invokedToolPaths(in: transcript)

        // 1. Valid answer — the reply carries fixture-grounded content and
        //    isn't a failure phrasing that happens to embed a required word.
        #expect(
            answerContainsOneOf.contains { response.content.localizedCaseInsensitiveContains($0) },
            "[\(name)] expected the answer to contain one of \(answerContainsOneOf), got \"\(response.content)\""
        )
        for forbidden in answerMustNotContain {
            #expect(
                !response.content.localizedCaseInsensitiveContains(forbidden),
                "[\(name)] the answer contains \"\(forbidden)\", which invalidates it: \"\(response.content)\""
            )
        }

        // 2. Grounded answer — produced through the tools surface at all,
        //    by any route.
        #expect(
            !invoked.isEmpty,
            "[\(name)] expected the answer to be grounded in at least one tools.* call, but no runCode snippet invoked any"
        )

        // 3. Claimed side effects really happened — containment, never
        //    equality; extra calls and any ordering are fine.
        if !mustInvoke.isEmpty {
            #expect(
                mustInvoke.isSubset(of: invoked),
                "[\(name)] the answer claims an action that requires invoking \(mustInvoke.sorted()), but only \(invoked.sorted()) were invoked"
            )
        }

        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log)" — the route details stay visible here as
        // diagnostics (see also `PrefixReuseTests` for the prefix-reuse
        // measurement's own recorded evidence), they just no longer gate.
        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(NativeTranscript.toolCallCount(in: transcript)) "
                + "invoked=\(invoked.sorted()) "
                + "findAPIsFirst=\(NativeTranscript.findAPIsPrecedesRunCode(in: transcript)) "
                + "reply=\"\(response.content.prefix(80))\""
        )
        await fixture.tearDown()
    } catch GenerationError.notWiredForLiveInference {
        print("SKIP [\(name)]: Router's live-inference path is not wired up in this environment.")
        await fixture.tearDown()
    } catch {
        await fixture.tearDown()
        throw error
    }
}
