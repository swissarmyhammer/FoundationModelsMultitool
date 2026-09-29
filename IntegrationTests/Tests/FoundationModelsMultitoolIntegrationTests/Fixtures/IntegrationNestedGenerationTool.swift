import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import ScenarioGrading

@testable import FoundationModelsMultitool

// The one fixture tool that stays in the gated package. Every other fixture
// reads plain values and stands in `ScenarioGrading`, where the root test
// target links it. This one opens a nested generation on a resolved slot, so
// it drives a model and belongs here. It also records its call as a span with
// an enter record through `TracedCall.run`, and it writes that record through
// `MultitoolTelemetry.logger`, which is `internal` to the shipped library —
// reaching it needs the `@testable` import above, which a support library
// cannot carry.
//
// `integrationNestedGenerationPath`, `integrationNestedGenerationToken` and
// `NestedGenerationOutcome` stay in `ScenarioGrading`: the grading rule and
// its ungated coverage read them, and both name the same values this file
// does.

/// `IntegrationNestedGenerationTool`'s output.
@Generable(description: "the readiness token the nested check produced.")
struct IntegrationNestedGenerationOutput {
    var readinessToken: String
}

/// The prompt the nested session is given.
///
/// Deliberately trivial, and deliberately ungraded. The probe asks how the
/// nested call **ends**, not what it says, so a prompt with any substance
/// would only add ways for a run to be slow without adding anything to read.
let integrationNestedGenerationPrompt = "Say hello."

/// How many tokens the nested generation is allowed.
///
/// Small on purpose. On the work-queue Router the nested call is refused
/// before it generates anything. When a later Router lets it through, this
/// cap keeps that nested turn to seconds, so the probe reports the changed
/// behavior as a `returned` outcome and not as a time-limit failure.
let integrationNestedGenerationTokenLimit = 32

/// The record of how the nested call of the probe ended.
///
/// An `actor` because the tool body writes it from inside a tool call, and
/// the probe runner reads it after the turn ends.
actor NestedGenerationOutcomeLog {
    /// How the nested call ended, or `nil` when no nested call ended.
    private(set) var outcome: NestedGenerationOutcome?

    /// Records how the nested call ended.
    ///
    /// - Parameter ended: how the nested call ended.
    func record(_ ended: NestedGenerationOutcome) {
        outcome = ended
    }
}

/// The tool the nested-generation probe drives: its body opens a plain session
/// on the very model the outer turn is running on, and generates.
///
/// **What it is for.** `searchTools` generates from inside the outer turn's
/// tool call. When one model serves both profile slots, that nested
/// generation needs the model that the outer submission holds open. The old
/// Router hung for ever there. The work-queue Router refuses it at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`, because the queue
/// sees that the outer submission of the same model is open
/// (`GenerationQueue.refuseWaitInsideOpenSubmission()`). This fixture makes
/// that nested call and records how it ended, with the time it took, in a
/// `NestedGenerationOutcomeLog`. `nestedGenerationChecks(for:)` grades the
/// record.
///
/// **No grammar.** The body calls `makeSession()` with every argument
/// defaulted: no `Grammar`, no selection tier, no `MetadataSearcher`. The
/// refusal is a property of the queue, and a grammar in the run would only add
/// a second thing to read.
///
/// **Why the same slot.** `slot` is the resolved `.standard` the outer turn is
/// already running on, so the nested session shares that model's queue by
/// construction — the condition under test, rather than something that
/// happens to hold when two pins collide.
///
/// **Why the output is not a `String`.** Router's session mount wraps a
/// `Tool<_, String>` in `BackgroundToolRunner` and leaves every other tool in band
/// (`ToolMounting.makeWrapped(tool:sessionID:mailbox:sink:configuration:)`). A
/// background body runs outside the open submission, where the queue has
/// nothing to refuse — and would make this probe answer a question nobody
/// asked. A `@Generable` output keeps the call in band.
///
/// **Why the call returns normally after the refusal.** The tool catches the
/// refusal and reports the readiness token, so the outer turn ends at once.
/// The verdict reads the outcome log, never the reply.
struct IntegrationNestedGenerationTool: Tool {
    /// The name of the span of this fixture's nested call.
    ///
    /// A suspended `async` call occupies no thread, so `sample` and `spindump`
    /// name nothing when this hangs — see
    /// `MultitoolTelemetry.SpanName`. The call opens its span through
    /// `TracedCall.run`, which writes the record `enter <this name>` when the
    /// call starts. That record with no ended span is the whole evidence a
    /// hung run leaves. The name is not in the vocabulary of the library,
    /// because only this test fixture opens the span.
    private static let spanName = "FoundationModelsMultitoolIntegrationTests.nestedRespond"

    let name = integrationNestedGenerationPath
    let description = "Checks that the assistant's own language model is responsive right now, and "
        + "returns the readiness token that check produced. Takes no arguments."

    /// The resolved slot the outer turn is running on — the same one, on
    /// purpose.
    let slot: RoutedLLM

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// The record this tool writes the outcome of its nested call into.
    let outcomes: NestedGenerationOutcomeLog

    /// Generates on ``slot`` from inside this tool call, records how that
    /// nested call ended, then reports the readiness token.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: the fixture readiness token.
    /// - Throws: a `CancellationError` when the outer turn is cancelled.
    func call(arguments: IntegrationNoArguments) async throws -> IntegrationNestedGenerationOutput {
        try await log.recordCall(to: name) {
            try await TracedCall.run(Self.spanName, logger: MultitoolTelemetry.logger) { _ in
                await outcomes.record(await nestedCallOutcome())
                try Task.checkCancellation()
                return IntegrationNestedGenerationOutput(readinessToken: integrationNestedGenerationToken)
            }
        }
    }

    /// Makes the nested call on ``slot`` and says how it ended.
    ///
    /// - Returns: `.refused` with the time the refusal took, `.returned` when
    ///   the nested call gave a reply, or `.threw` for any other error.
    private func nestedCallOutcome() async -> NestedGenerationOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await slot.makeSession().respond(
                to: integrationNestedGenerationPrompt,
                maxTokens: integrationNestedGenerationTokenLimit
            )
            return .returned
        } catch GenerationQueueError.waitInsideOpenSubmission {
            return .refused(after: clock.now - start)
        } catch {
            return .threw(description: "\(error)")
        }
    }
}
