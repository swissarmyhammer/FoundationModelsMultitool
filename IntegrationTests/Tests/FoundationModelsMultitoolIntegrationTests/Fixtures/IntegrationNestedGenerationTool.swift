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
/// Small on purpose. The nested call generates on the outer answer's own
/// model, and this cap keeps that generation to seconds.
let integrationNestedGenerationTokenLimit = 32

/// The record of how the nested call of the probe ended.
///
/// An `actor` because the tool body writes it from inside a tool call, and
/// the probe runner reads it after the answer ends.
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
/// on the very model that the outer answer runs on, and generates.
///
/// **What it is for.** `searchTools` generates from inside a tool call of the
/// outer answer. When one model serves the outer answer and the nested call,
/// that nested generation needs the model of the outer answer. The old Router
/// hung for ever there, and the work-queue Router after it refused the call
/// with `waitInsideOpenSubmission`. Since Router `505a03f3` the lock is held
/// over the call into the model only, never over a tool call: the SDK runs
/// this tool body after the outer `respond` returns, so the nested call takes
/// the lock in its turn and completes. This fixture makes that nested call and
/// records how it ended in a `NestedGenerationOutcomeLog`.
/// `nestedGenerationChecks(for:)` grades the record.
///
/// **No grammar.** The body calls `makeSession()` with every argument
/// defaulted: no `Grammar`, no selection tier, no `MetadataSearcher`. The
/// question is the lock, and a grammar in the run would only add a second
/// thing to read.
///
/// **Why the same slot.** `slot` is the resolved `.standard` that the outer
/// answer already runs on, so the nested session shares that model by
/// construction — the condition under test, rather than something that
/// happens to hold when two pins collide. The nested session is a new
/// session: a wait for the tool's own session is the one wait Router still
/// refuses in band (`RoutedSessionError.inBandWaitForOwnSession`).
///
/// **Why the output is not a `String`.** Router's session mount wraps a
/// `Tool<_, String>` in `BackgroundToolRunner` and leaves every other tool in band
/// (`ToolMounting.makeWrapped(tool:site:configuration:)`). A background body
/// runs apart from the answer, and would make this probe answer a question
/// nobody asked. A `@Generable` output keeps the call in band.
///
/// **Why the call returns normally after an error.** The tool catches what the
/// nested call throws and reports the readiness token, so the outer answer
/// ends at once. The verdict reads the outcome log, never the reply.
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

    /// The resolved slot that the outer answer runs on. It is the same slot
    /// on purpose.
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
    /// - Throws: a `CancellationError` when the outer answer is cancelled.
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
    /// - Returns: `.returned` when the nested call gave a reply, or `.threw`
    ///   with the error.
    private func nestedCallOutcome() async -> NestedGenerationOutcome {
        // The nested session is a Router session. It is closed on each path,
        // thus it keeps no hold of the profile after this call.
        let nested = slot.makeSession()
        do {
            _ = try await nested.respond(
                to: integrationNestedGenerationPrompt,
                maxTokens: integrationNestedGenerationTokenLimit
            )
            await nested.close()
            return .returned
        } catch {
            await nested.close()
            return .threw(description: "\(error)")
        }
    }
}
