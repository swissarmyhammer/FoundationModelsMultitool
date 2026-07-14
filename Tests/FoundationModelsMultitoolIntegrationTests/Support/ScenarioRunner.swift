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
/// decide when to call each. Assertions read the session's own
/// `FoundationModels.Transcript` via `NativeTranscript`'s helpers — no
/// Router-recorded JSONL/`AgentStep` parsing, except for
/// `expectedFoundApiNames`, which still reads `findAPIsTool`'s own
/// selection-tier `.flash`-slot recording, since that tier remains
/// Router-backed (task `4aveepp`'s decision, kept specifically to preserve
/// `PrefixReuseTests`' fork()-based prefix-reuse property).
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
///   - expectFindApis: whether the scenario expects `findAPIs` to precede
///     `runCode` (the "search-then-code" trace assertion).
///   - expectedToolPaths: the exact `tools.*` call paths every `runCode`
///     call's snippet is expected to invoke (unioned across every call), or
///     `nil` to skip that assertion.
///   - expectedFoundApiNames: the exact entry paths the selection tier is
///     expected to have selected across every `findAPIs` call in the run, or
///     `nil` to skip that assertion.
///   - maxRunCodeCallsBeforeFinal: the bound a repair scenario's "repaired
///     within N calls" assertion checks against, or `nil` to skip it. Every
///     `runCode` call in a single `session.respond(to:)` run necessarily
///     precedes its one final answer, so this is simply the total `runCode`
///     call count.
/// - Throws: any error other than `GenerationError.notWiredForLiveInference`
///   — including a failed `#expect` (Swift Testing turns a failed
///   expectation into a recorded issue, not a thrown error, so this
///   signature only actually throws for genuine setup/dispatch failures).
func runNativeIntegrationScenario(
    name: String,
    tools: [any Tool],
    prompt: String,
    expectFindApis: Bool,
    expectedToolPaths: Set<String>? = nil,
    expectedFoundApiNames: Set<String>? = nil,
    maxRunCodeCallsBeforeFinal: Int? = nil
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
            instructions: "You are a helpful assistant. Use runCode to get things done."
        )

        let start = Date()
        // Explicitly typed to pin the native FoundationModels API over
        // `FoundationModelsRanker`'s shadowing `respond(to:) -> String`
        // `AgentSession` extension.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let transcript = session.transcript

        if expectFindApis {
            #expect(
                NativeTranscript.findAPIsPrecedesRunCode(in: transcript),
                "[\(name)] expected findAPIs before runCode"
            )
        }
        if let expectedToolPaths {
            #expect(
                NativeTranscript.invokedToolPaths(in: transcript) == expectedToolPaths,
                "[\(name)] expected exactly \(expectedToolPaths) tools.* calls"
            )
        }
        if let expectedFoundApiNames {
            let events = try fixture.transcriptEvents()
            let picked = try NativeTranscript.selections(in: events, slot: .flash).flatMap(\.ids)
            #expect(
                Set(picked) == expectedFoundApiNames,
                "[\(name)] expected the selection tier to select exactly \(expectedFoundApiNames), got \(Set(picked))"
            )
        }
        if let maxRunCodeCallsBeforeFinal {
            let calls = NativeTranscript.toolCallCount(in: transcript, named: multiTool.name)
            #expect(
                calls <= maxRunCodeCallsBeforeFinal,
                "[\(name)] expected repair within \(maxRunCodeCallsBeforeFinal) runCode calls, got \(calls)"
            )
        }

        // plan.md acceptance: "the per-format results are recorded (test
        // attachment or log)" — this is the log half of that (see also
        // `PrefixReuseTests` for the prefix-reuse measurement's own recorded
        // evidence).
        print(
            "RESULT [\(name)] elapsed=\(elapsed)s toolCalls=\(NativeTranscript.toolCallCount(in: transcript)) "
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
