import Testing

import Evaluations
import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// plan.md M6.5b: "score the agent as an eval, not string-equality tests" —
/// an `Evaluations.Evaluation` conformer whose `subject(from:)` runs
/// `MultiToolAgent.respond(to:)` end to end, over a live Router profile, for
/// each of the four M6.5a sample MultiTool scenarios
/// (`Fixtures/ScenarioTools.swift`), then grades the recorded run with the
/// deterministic evaluators from `Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift`
/// (`SearchedThenCalledEvaluator`, `CalledExpectedToolsEvaluator`,
/// `RepairedWithinNEvaluator`) — the *same* conformers
/// `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` proves
/// ungated against checked-in fixture transcripts, so this file adds only
/// the live-model wiring, never a second copy of the grading logic.
///
/// **SDK pin, resolved against the shipping OS-27 SDK** (`Evaluations
/// .swiftmodule`'s `.swiftinterface`, found under
/// `.../MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework`
/// — the framework *does* ship, unlike the possibility plan.md's pin note
/// flagged): member names mostly match plan.md's guesses
/// (`Evaluation`, `ArrayLoader`, `ModelSample`, `Metric`,
/// `aggregateMetrics(using:)`, `computeMean`/`computeStandardDeviation`,
/// `.evaluates(_:info:)`, `EvaluationContext.current.result
/// .aggregateValue(_:)`, `AggregationOperation.mean(of:)`), with these
/// concrete deviations:
///
/// - `Metric.score(_:)` (plan.md's guess) is actually `Metric
///   .scoring(_:rationale:)`; not used here since every metric in this
///   suite is deterministic pass/fail/ignore.
/// - `Evaluation.Sample`/`Subject` are separate associated types (`Sample
///   .ExpectedValue == Subject.Value`), and the library-provided `Evaluator
///   <Input>` (a closure-based convenience conformer) hard-codes `Subject ==
///   ModelSubject<Input.ExpectedValue>`. Grading this package's own
///   recorded Router transcript (not an Apple `FoundationModels.Transcript`)
///   needs a custom `Subject` carrying `[AgentStep]`, so this evaluation
///   uses a direct `EvaluatorProtocol` conformance
///   (`AgentSubject`/`SearchedThenCalledEvaluator`/etc. in
///   `AgentEvaluators.swift`) instead of the `Evaluator<Input>` convenience.
/// - `ModelSample.expectations: TrajectoryExpectation?` — graded by `Evaluations
///   .ToolCallEvaluator` against `Evaluations.StructuredTranscript`, both of
///   which read `FoundationModels.Transcript.ToolCall` — does not apply:
///   `MultiToolAgent` never produces an Apple `Transcript` (see
///   `AgentScenarioExpectation`'s documentation for the full reasoning), so
///   each scenario's expected tool paths/repair bound travel on `AgentSubject`
///   instead.
/// - `SampleGenerator.makeSamples(…, targetCount:)` (plan.md's "optionally
///   widen with paraphrase/distractor variants") is real and available, but
///   deliberately not used here: widening the dataset needs a working
///   generation session purely to *synthesize more prompts*, an extra
///   moving part this task's scope doesn't require to prove the
///   search-then-call thesis on the four scenarios already gating M6.5a.
/// - `ModelJudgeEvaluator` (plan.md's optional final-answer-quality judge)
///   is likewise real (`ScoringScale.numeric(_:)`, `ScoreDimension`, a
///   `judge: any FoundationModels.LanguageModel` defaulting to
///   `SystemLanguageModel()`) but omitted: plan.md marks it optional, and
///   this suite's three deterministic metrics already cover the
///   acceptance criteria's gate.
struct AgentEvaluation: Evaluation {
    typealias Sample = ModelSample<String>
    typealias Subject = AgentSubject
    typealias SampleLoader = ArrayLoader<ModelSample<String>>

    /// One M6.5 sample MultiTool scenario: the prompt to drive
    /// `MultiToolAgent.respond(to:)` with, the tool set to wrap, and the
    /// scenario's grading configuration. Every `prompt` across `scenarios`
    /// must be textually unique — `subject(from:)` looks a scenario up by
    /// its sample's `promptDescription`.
    private struct Scenario {
        let prompt: String
        let tools: [any Tool]
        let expectation: AgentScenarioExpectation
    }

    /// The four M6.5a sample MultiTool scenarios (`SearchThenCallTests`),
    /// reused here as this evaluation's dataset — plan.md M6.5b: "Dataset:
    /// ... built from the four M6.5a scenarios." Tools and expectations are
    /// verbatim; scenario 3's prompt is deliberately reworded (see its own
    /// comment below) so every scenario's prompt text is unique, since
    /// `subject(from:)` looks a scenario up by its sample's prompt. Each
    /// scenario runs under `MultiToolAgent`'s default turn format
    /// (`.tolerantParse()`); M6.5a's own gated suite is what settles the
    /// `.tolerantParse` vs. `.guided` question empirically, so this
    /// evaluation doesn't duplicate that comparison.
    private static let scenarios: [Scenario] = [
        // Scenario 1: single-call `weather`.
        Scenario(
            prompt: "How warm is it in Austin right now?",
            tools: [IntegrationWeatherTool()],
            expectation: AgentScenarioExpectation(
                expectFindAPIs: true,
                expectedToolPaths: ["weather"],
                maxRunCodeStepsBeforeFinal: 1
            )
        ),
        // Scenario 2: compose/chain tripCities -> weather -> warmest.
        Scenario(
            prompt: "Of the cities on my trip, which is warmest right now?",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            expectation: AgentScenarioExpectation(
                expectFindAPIs: true,
                expectedToolPaths: ["tripCities", "weather"],
                maxRunCodeStepsBeforeFinal: 1
            )
        ),
        // Scenario 3: discovery under ~20 distractors. Rephrased slightly
        // from scenario 2's prompt so every scenario's prompt text is
        // unique (this evaluation's dataset/subject lookup key), while
        // asking the same underlying question over a much larger surface.
        Scenario(
            prompt: "Of all the trip-planning tools available, which city on my trip is warmest right now?",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            expectation: AgentScenarioExpectation(
                expectFindAPIs: true,
                expectedToolPaths: ["tripCities", "weather"],
                maxRunCodeStepsBeforeFinal: 1
            )
        ),
        // Scenario 4: repair from a trip-prone tool.
        Scenario(
            prompt: "Confirm my booking, id 42.",
            tools: [IntegrationBookingTool()],
            expectation: AgentScenarioExpectation(
                expectFindAPIs: false,
                expectedToolPaths: ["book"],
                maxRunCodeStepsBeforeFinal: 3
            )
        ),
    ]

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Self.scenarios.map { ModelSample(prompt: $0.prompt) })
    }

    /// Runs one scenario's prompt through a freshly-resolved live
    /// `MultiToolAgent`, then reduces the resulting Router JSONL transcript
    /// to an `AgentSubject` the evaluators above grade — mirroring
    /// `ScenarioRunner.runIntegrationScenario(...)` (M6.5a): a fresh
    /// `LiveRouterFixture` per scenario (never shared across samples), so
    /// each subject's transcript reflects only that scenario's own run, not
    /// every prior sample's accumulated history on the same resident
    /// profile.
    ///
    /// - Parameter sample: the dataset sample to run.
    /// - Returns: the subject the evaluators above grade.
    /// - Throws: `GenerationError.notWiredForLiveInference` if the Router's
    ///   live decode path isn't wired up in this environment; an
    ///   `AgentEvaluationError.unknownScenario` if `sample`'s prompt
    ///   doesn't match any entry in `scenarios` (an invariant violation of
    ///   this evaluation's own wiring, since `dataset` is derived from the
    ///   same `scenarios` list); or whatever running the agent itself
    ///   throws.
    func subject(from sample: ModelSample<String>) async throws -> AgentSubject {
        guard let scenario = Self.scenarios.first(where: { $0.prompt == sample.promptDescription }) else {
            throw AgentEvaluationError.unknownScenario(prompt: sample.promptDescription)
        }

        let fixture = try await LiveRouterFixture.resolve()
        do {
            let registry = try MultiTool.Builder().addTools(scenario.tools).buildRegistry()
            let agent = MultiToolAgent(
                registry: registry,
                model: fixture.profile.standard,
                librarian: fixture.profile.flash,
                instructions: "You are a helpful assistant. Use runCode to get things done."
            )
            let reply = try await agent.respond(to: scenario.prompt)
            let events = try fixture.transcriptEvents()
            let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
            await fixture.tearDown()
            return AgentSubject(value: reply, steps: steps, expectation: scenario.expectation)
        } catch {
            await fixture.tearDown()
            throw error
        }
    }

    @EvaluatorsBuilder<Sample, Subject> var evaluators: Evaluators {
        SearchedThenCalledEvaluator()
        CalledExpectedToolsEvaluator()
        RepairedWithinNEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Metric(AgentMetricName.searchedThenCalled))
        aggregator.computeStandardDeviation(of: Metric(AgentMetricName.searchedThenCalled))
        aggregator.computeMean(of: Metric(AgentMetricName.calledExpectedTools))
        aggregator.computeStandardDeviation(of: Metric(AgentMetricName.calledExpectedTools))
        aggregator.computeMean(of: Metric(AgentMetricName.repairedWithinN))
        aggregator.computeStandardDeviation(of: Metric(AgentMetricName.repairedWithinN))
    }
}

/// A failure specific to `AgentEvaluation`'s own dataset/subject wiring —
/// never expected in practice since `dataset` and `subject(from:)` are both
/// derived from the same `AgentEvaluation.scenarios` list.
enum AgentEvaluationError: Error, CustomStringConvertible {
    /// `subject(from:)` received a sample whose prompt matches no entry in
    /// `AgentEvaluation.scenarios`.
    case unknownScenario(prompt: String)

    var description: String {
        switch self {
        case .unknownScenario(let prompt):
            return "AgentEvaluation: no scenario registered for prompt \"\(prompt)\"."
        }
    }
}

/// M6.5b's gated eval suite: the same `MULTITOOL_INTEGRATION` opt-in env
/// var as M6.5a's `SearchThenCallTests`/`PrefixReuseTests` — unset (the
/// default), `.enabled(if:)` skips the whole suite before `.evaluates(...)`
/// ever invokes `AgentEvaluation.subject(from:)`, so `swift test` stays
/// green with zero downloads and zero live inference, exactly like M6.5a.
@Suite(
    "Evaluations-framework eval suite grading search-then-call (M6.5b)",
    .enabled(if: multitoolIntegrationEnabled),
    .timeLimit(.minutes(30))
)
struct AgentEvaluationTests {
    /// The mean-aggregate pass threshold plan.md's own worked gate example
    /// uses — tunable per metric, but kept uniform here since all three
    /// metrics are graded pass/fail/ignore over the same four scenarios.
    private static let passThreshold = 0.9

    @Test(.evaluates(AgentEvaluation(), info: ["suite": "M6.5b"]))
    func searchThenCallEvaluation() throws {
        let result = EvaluationContext.current.result
        #expect(
            result.aggregateValue(.mean(of: Metric(AgentMetricName.searchedThenCalled))) >= Self.passThreshold,
            "SearchedThenCalled mean below threshold:\n\(result.groupedSummary)"
        )
        #expect(
            result.aggregateValue(.mean(of: Metric(AgentMetricName.calledExpectedTools))) >= Self.passThreshold,
            "CalledExpectedTools mean below threshold:\n\(result.groupedSummary)"
        )
        #expect(
            result.aggregateValue(.mean(of: Metric(AgentMetricName.repairedWithinN))) >= Self.passThreshold,
            "RepairedWithinN mean below threshold:\n\(result.groupedSummary)"
        )
    }
}
