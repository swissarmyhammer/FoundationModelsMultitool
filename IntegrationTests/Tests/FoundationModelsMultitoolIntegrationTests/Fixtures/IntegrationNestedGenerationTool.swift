import FoundationModels
import FoundationModelsRouter
import ScenarioGrading

@testable import FoundationModelsMultitool

// The one fixture tool that stays in the gated package. Every other fixture
// reads plain values and stands in `ScenarioGrading`, where the root test
// target links it. This one opens a nested generation on a resolved slot, so
// it drives a model and belongs here. It also records its call as a
// `CallTrace` span, and `CallTrace` is `internal` to the shipped library —
// reaching it needs the `@testable` import above, which a support library
// cannot carry.
//
// `integrationNestedGenerationPath` and `integrationNestedGenerationToken`
// stay in `ScenarioGrading`: the grading rule and its ungated coverage read
// them, and both name the same strings this file does.

/// `IntegrationNestedGenerationTool`'s output.
@Generable(description: "the readiness token the nested check produced.")
struct IntegrationNestedGenerationOutput {
    var readinessToken: String
}

/// The prompt the nested session is given.
///
/// Deliberately trivial, and deliberately ungraded. The probe asks whether the
/// nested call **returns**, not what it says, so a prompt with any substance
/// would only add ways for a run to be slow without adding anything to read.
let integrationNestedGenerationPrompt = "Say hello."

/// How many tokens the nested generation is allowed.
///
/// Small on purpose, and load-bearing for the probe's verdict. A model that
/// reasons before it answers — Muse Glimmer, which held the slot when this
/// was measured, cannot be asked not to — can spend minutes on an uncapped
/// nested turn, and a suite whose own limit is three minutes
/// would then report a slow call and a deadlocked call identically. A cap this
/// tight makes a live nested turn a matter of seconds, so the limit can only be
/// reached by a call that is not running at all.
let integrationNestedGenerationTokenLimit = 32

/// The tool the nested-generation probe drives: its body opens a plain session
/// on the very model the outer turn is running on, and generates.
///
/// **What it is for.** A gated scenario hangs for ever — 0% CPU, ~19GB
/// resident, every thread parked — when both profile slots name one `ModelRef`,
/// because `searchTools` generates from inside the outer turn's tool call. Two
/// explanations fit that picture, and this fixture separates them:
///
/// - the nested **grammar-constrained** decode deadlocks in MLX, whose xgrammar
///   path keeps shared per-model caches; or
/// - Router's `RoutedModel.generationGate` — an `AsyncSemaphore(value: 1)`
///   minted per resident container — is taken by `beginTurn()` and held for the
///   whole turn, tool calls included, so a nested `respond` on that container
///   parks on `generationGate.wait()` and can never be admitted: the permit is
///   handed back by `endTurn()`, which needs the tool call to return, which
///   needs the nested `respond`.
///
/// The second explanation needs no grammar. The first needs one. So this body
/// carries no grammar anywhere: `makeSession()` with every argument defaulted,
/// no `Grammar`, no selection tier, no `MetadataSearcher`. A hang here belongs
/// to the gate; a return here leaves the grammar as the thing that matters.
///
/// It hung, on 2026-08-16: 165 seconds inside this one call with the gate at
/// zero permits and one waiter throughout, unwound only when the suite's time
/// limit cancelled the outer turn. `runNestedGenerationProbe` records the whole
/// reading. So this call deadlocks today, and the fixture is unchanged by that
/// — it is what the regression test drives, and it will come back when the gate
/// lets a nested generation in.
///
/// **Why the same slot.** `slot` is the resolved `.standard` the outer turn is
/// already running on, so the nested session shares that container's gate by
/// construction — the condition under test, rather than something that happens
/// to hold when two pins collide.
///
/// **Why the output is not a `String`.** Router's session mount wraps a
/// `Tool<_, String>` in `BackgroundToolRunner` and leaves every other tool in band
/// (`ToolMounting.makeWrapped(tool:sessionID:mailbox:sink:configuration:)`). A
/// background body would run outside the turn that holds the permit, which is the
/// one arrangement that cannot deadlock — and would make this probe answer a
/// question nobody asked. A `@Generable` output keeps the call in band.
struct IntegrationNestedGenerationTool: Tool {
    /// Where this fixture's nested call is recorded as a span.
    ///
    /// A suspended `async` call occupies no thread, so `sample` and `spindump`
    /// name nothing when this hangs — see ``CallTrace``. The entry line with no
    /// matching exit line is the whole evidence a deadlocked run leaves.
    private static let trace = CallTrace(category: "NestedGenerationProbe")

    let name = integrationNestedGenerationPath
    let description = "Checks that the assistant's own language model is responsive right now, and "
        + "returns the readiness token that check produced. Takes no arguments."

    /// The resolved slot the outer turn is running on — the same one, on
    /// purpose.
    let slot: RoutedLLM

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Generates on ``slot`` from inside this tool call, then reports the
    /// readiness token.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: the fixture readiness token.
    /// - Throws: whatever the nested `respond(to:maxTokens:)` throws.
    func call(arguments: IntegrationNoArguments) async throws -> IntegrationNestedGenerationOutput {
        try await log.recordCall(to: name) {
            try await Self.trace.span("nestedRespond", detail: name) {
                _ = try await slot.makeSession().respond(
                    to: integrationNestedGenerationPrompt,
                    maxTokens: integrationNestedGenerationTokenLimit
                )
                return IntegrationNestedGenerationOutput(readinessToken: integrationNestedGenerationToken)
            }
        }
    }
}
