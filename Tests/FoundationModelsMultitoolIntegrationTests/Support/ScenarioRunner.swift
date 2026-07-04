import Foundation
import Testing

import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// Runs one M6.5 gated scenario end to end against a freshly-resolved live
/// profile, then asserts the requested trace properties via
/// `TranscriptAnalyzer` over the real Router JSONL transcript the run
/// produced — plan.md's "Assert on the loop, not just the final string."
///
/// **Skip, not failure.** Per plan.md M6.5, "skip cleanly... until the
/// Router's live-inference milestone lands": if resolving the profile or
/// running the agent throws `GenerationError.notWiredForLiveInference`, this
/// function prints a note and returns *without recording any issue* — Swift
/// Testing reports a test with no recorded issues as passed, so the suite
/// stays green rather than failing when live inference isn't wired up in
/// this environment. Any other error (a genuine scenario failure, a
/// download/network failure, etc.) propagates as an ordinary test failure —
/// real signal once a caller has opted in via `MULTITOOL_INTEGRATION` on
/// capable hardware.
///
/// - Parameters:
///   - name: a short label identifying the scenario, used only in the
///     printed result/skip line.
///   - tools: the scenario's fixed tool set.
///   - prompt: the user request driving `MultiToolAgent.respond(to:)`.
///   - turnFormat: the turn strategy under test (`.tolerantParse()` or
///     `.guided()`).
///   - expectFindAPIs: whether the scenario expects `findAPIs` to precede
///     `runCode` (plan.md's "search-then-code" trace assertion).
///   - expectedToolPaths: the exact `tools.*` call paths the snippet is
///     expected to invoke, or `nil` to skip that assertion.
///   - expectedFoundAPINames: the exact entry paths the selection tier is
///     expected to have selected across every `findAPIs` call in the run
///     (plan.md's "librarian returned the expected minimal set" trace
///     assertion — the fused-surface selection-accuracy claim scenario 3
///     exists to prove), or `nil` to skip that assertion.
///   - maxRunCodeStepsBeforeFinal: the bound the repair scenario's "repaired
///     within N turns" assertion checks against, or `nil` to skip it.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`
///   — including a failed `#expect` (Swift Testing turns a failed
///   expectation into a recorded issue, not a thrown error, so this signature
///   only actually throws for genuine setup/dispatch failures).
func runIntegrationScenario(
    name: String,
    tools: [any Tool],
    prompt: String,
    turnFormat: any TurnFormat,
    expectFindAPIs: Bool,
    expectedToolPaths: Set<String>? = nil,
    expectedFoundAPINames: Set<String>? = nil,
    maxRunCodeStepsBeforeFinal: Int? = nil
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
        let agent = try MultiToolAgent(
            registry: registry,
            model: fixture.profile.standard,
            librarian: fixture.profile.flash,
            instructions: "You are a helpful assistant. Use runCode to get things done.",
            turnFormat: turnFormat
        )

        let start = Date()
        let reply = try await agent.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let events = try fixture.transcriptEvents()
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)

        if expectFindAPIs {
            #expect(
                TranscriptAnalyzer.findAPIsPrecedesRunCode(in: steps),
                "[\(name)] expected findAPIs before runCode"
            )
        }
        if let expectedToolPaths {
            #expect(
                TranscriptAnalyzer.invokedToolPaths(in: steps) == expectedToolPaths,
                "[\(name)] expected exactly \(expectedToolPaths) tools.* calls"
            )
        }
        if let expectedFoundAPINames {
            let picked = try TranscriptAnalyzer.selections(in: events, slot: .flash)
                .flatMap(\.ids)
            #expect(
                Set(picked) == expectedFoundAPINames,
                "[\(name)] expected the selection tier to select exactly \(expectedFoundAPINames), got \(Set(picked))"
            )
        }
        if let maxRunCodeStepsBeforeFinal {
            let attempts = TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps)
            #expect(
                attempts <= maxRunCodeStepsBeforeFinal,
                "[\(name)] expected repair within \(maxRunCodeStepsBeforeFinal) runCode attempts, got \(attempts)"
            )
        }

        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log) to settle the M4b/M4c default" — this is the
        // log half of that (see also `PrefixReuseTests` for the prefix-reuse
        // measurement's own recorded evidence).
        print(
            "RESULT [\(name)] turnFormat=\(type(of: turnFormat)) elapsed=\(elapsed)s "
                + "steps=\(steps.count) reply=\"\(reply.prefix(80))\""
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
