import Evaluations
import FoundationModels
import FoundationModelsRouter

/// Deterministic pass/fail metric names this package's `Evaluations`
/// conformers grade — plan.md M6.5: `Metric("SearchedThenCalled")`,
/// `Metric("CalledExpectedTools")`, `Metric("RepairedWithinN")`.
///
/// Named constants (not repeated string literals) so an evaluator's own
/// `Metric(_:)` construction and a caller's aggregation-gate reference
/// (`aggregator.computeMean(of: Metric(AgentMetricName.searchedThenCalled))`)
/// can never drift apart.
public enum AgentMetricName {
    /// plan.md's "SearchedThenCalled" metric — a `findAPIs` step preceded
    /// the first `runCode` step.
    public static let searchedThenCalled = "SearchedThenCalled"
    /// plan.md's "CalledExpectedTools" metric — the snippet(s) invoked
    /// exactly the scenario's expected `tools.*` paths.
    public static let calledExpectedTools = "CalledExpectedTools"
    /// plan.md's "RepairedWithinN" metric — the run used at most a bounded
    /// number of `runCode` attempts before either reaching `.final` or
    /// exhausting its steps.
    public static let repairedWithinN = "RepairedWithinN"
}

/// One scenario's grading configuration for `AgentEvaluation`'s
/// deterministic evaluators below — plan.md M6.5's four sample MultiTool
/// scenarios (M6.5a), reduced to exactly what grading a recorded run needs:
/// whether `findAPIs` is expected to precede `runCode` at all, which
/// `tools.*` paths the snippet is expected to invoke, and the repair bound.
///
/// **Deviation from plan.md, resolved against the shipping SDK's
/// `.swiftinterface` (`Evaluations.swiftmodule`):** `Evaluations
/// .ModelSample`'s own `expectations: TrajectoryExpectation?` field looks
/// like the natural home for this, but `TrajectoryExpectation` /
/// `ToolExpectation` are graded by `Evaluations.ToolCallEvaluator` against
/// `Evaluations.StructuredTranscript`, which is read off
/// `FoundationModels.Transcript` — Apple's *own* tool-calling session's
/// recorded transcript. `MultiToolAgent` never produces a
/// `FoundationModels.Transcript`: it drives its own agent loop over a
/// Router `RoutedSession`, and its tool calls live inside JavaScript
/// snippets the interpreter runs, not in an Apple session's tool-call
/// record. So `ToolCallEvaluator`/`StructuredTranscript` don't apply here,
/// and this scenario's expectations are carried on `AgentSubject` instead,
/// read back from the *real* recorded artifact this package does produce —
/// the Router JSONL transcript, via `TranscriptAnalyzer` — exactly as
/// `SearchThenCallTests`/`ScenarioRunner` (M6.5a) already does.
public struct AgentScenarioExpectation: Sendable {
    /// Whether a `.findAPIs` step is expected to precede the first
    /// `.runCode` step.
    ///
    /// `false` for a scenario (like M6.5a's repair scenario) that
    /// deliberately doesn't exercise discovery — in which case
    /// `SearchedThenCalledEvaluator` reports `Metric.ignore(rationale:)`
    /// rather than grading a property the scenario never claims to satisfy.
    public let expectFindAPIs: Bool

    /// The exact `tools.*` call paths the snippet(s) are expected to
    /// invoke — no more, no fewer.
    public let expectedToolPaths: Set<String>

    /// The maximum number of `.runCode` steps allowed before the first
    /// `.final` step — plan.md's "repaired within N turns" bound.
    public let maxRunCodeStepsBeforeFinal: Int

    /// Creates a scenario's grading configuration.
    ///
    /// - Parameters:
    ///   - expectFindAPIs: whether `findAPIs` is expected to precede
    ///     `runCode`.
    ///   - expectedToolPaths: the exact `tools.*` paths expected to be
    ///     invoked.
    ///   - maxRunCodeStepsBeforeFinal: the maximum `.runCode` attempts
    ///     allowed before `.final`.
    public init(expectFindAPIs: Bool, expectedToolPaths: Set<String>, maxRunCodeStepsBeforeFinal: Int) {
        self.expectFindAPIs = expectFindAPIs
        self.expectedToolPaths = expectedToolPaths
        self.maxRunCodeStepsBeforeFinal = maxRunCodeStepsBeforeFinal
    }
}

/// `AgentEvaluation`'s `Evaluations.EvaluationSubject` — one completed run
/// (a live `MultiToolAgent.respond(to:)` call in the gated suite, or a
/// replayed fixture transcript in the ungated threshold-gate proof),
/// reduced to exactly what the deterministic evaluators below need: the
/// final answer text (`value`, satisfying `EvaluationSubject.Value ==
/// String`), the main agent's parsed steps
/// (`TranscriptAnalyzer.steps(in:slot:)`, filtered to `.standard`), and the
/// scenario's grading configuration.
public struct AgentSubject: EvaluationSubject, Sendable {
    /// The agent's final answer text — `Evaluations.EvaluationSubject`'s
    /// required `value`.
    public let value: String

    /// The main agent's parsed steps, in recorded order — see
    /// `TranscriptAnalyzer.steps(in:slot:)`.
    public let steps: [AgentStep]

    /// This subject's scenario grading configuration.
    public let expectation: AgentScenarioExpectation

    /// Creates a subject.
    ///
    /// - Parameters:
    ///   - value: the agent's final answer text.
    ///   - steps: the main agent's parsed steps, in recorded order.
    ///   - expectation: the scenario's grading configuration.
    public init(value: String, steps: [AgentStep], expectation: AgentScenarioExpectation) {
        self.value = value
        self.steps = steps
        self.expectation = expectation
    }
}

/// plan.md's `Metric("SearchedThenCalled")` — passing when a `.findAPIs`
/// step precedes the first `.runCode` step (`TranscriptAnalyzer
/// .findAPIsPrecedesRunCode(in:)`), failing when it doesn't, and ignored for
/// a scenario that doesn't expect discovery at all (`AgentScenarioExpectation
/// .expectFindAPIs == false`) — deterministic, no judge model needed.
public struct SearchedThenCalledEvaluator: EvaluatorProtocol, Sendable {
    /// The evaluated sample type — `Evaluations.EvaluatorProtocol`'s `Input` requirement.
    public typealias Input = ModelSample<String>
    /// The evaluated subject type — `Evaluations.EvaluatorProtocol`'s `Subject` requirement.
    public typealias Subject = AgentSubject

    /// Creates the evaluator.
    ///
    /// No configuration: the metric it grades is fixed
    /// (`AgentMetricName.searchedThenCalled`), and the scenario's own
    /// expectation travels on the `Subject` it is called with.
    public init() {}

    /// Grades `subject.steps` against `AgentMetricName.searchedThenCalled`,
    /// returning one passing, failing, or ignored metric.
    ///
    /// - Parameters:
    ///   - subject: the completed run being graded; its `steps` and
    ///     `expectation` supply everything this evaluator needs.
    ///   - input: the sample `subject` was resolved from — unused here,
    ///     since all grading data travels on `subject` rather than `input`.
    /// - Returns: a single-element array holding one `Metric` for
    ///   `AgentMetricName.searchedThenCalled`: `.passing` if a `.findAPIs`
    ///   step precedes the first `.runCode` step, `.failing` if not, or
    ///   `.ignore` if the scenario doesn't expect discovery at all
    ///   (`AgentScenarioExpectation.expectFindAPIs == false`).
    /// - Throws: never, for this deterministic evaluator; `throws` is
    ///   `EvaluatorProtocol`'s requirement on `metrics(subject:input:)`.
    public func metrics(subject: AgentSubject, input: ModelSample<String>) async throws -> [Metric] {
        let metric = Metric(AgentMetricName.searchedThenCalled)
        guard subject.expectation.expectFindAPIs else {
            return [metric.ignore(rationale: "this scenario does not require findAPIs before runCode.")]
        }
        return [
            TranscriptAnalyzer.findAPIsPrecedesRunCode(in: subject.steps)
                ? metric.passing(rationale: "a findAPIs step preceded the first runCode step.")
                : metric.failing(rationale: "no findAPIs step preceded the first runCode step.")
        ]
    }
}

/// plan.md's `Metric("CalledExpectedTools")` — passing when the snippet(s)
/// invoked exactly the scenario's expected `tools.*` paths
/// (`TranscriptAnalyzer.invokedToolPaths(in:)`), failing otherwise —
/// deterministic, no judge model needed.
public struct CalledExpectedToolsEvaluator: EvaluatorProtocol, Sendable {
    /// The evaluated sample type — `Evaluations.EvaluatorProtocol`'s `Input` requirement.
    public typealias Input = ModelSample<String>
    /// The evaluated subject type — `Evaluations.EvaluatorProtocol`'s `Subject` requirement.
    public typealias Subject = AgentSubject

    /// Creates the evaluator.
    ///
    /// See `SearchedThenCalledEvaluator.init()`.
    public init() {}

    /// Grades `subject.steps` against `AgentMetricName.calledExpectedTools`,
    /// returning one passing or failing metric.
    ///
    /// - Parameters:
    ///   - subject: the completed run being graded; its `steps` and
    ///     `expectation.expectedToolPaths` supply everything this evaluator
    ///     needs.
    ///   - input: the sample `subject` was resolved from — unused here,
    ///     since all grading data travels on `subject` rather than `input`.
    /// - Returns: a single-element array holding one `Metric` for
    ///   `AgentMetricName.calledExpectedTools`: `.passing` if the invoked
    ///   `tools.*` paths exactly equal `subject.expectation
    ///   .expectedToolPaths`, `.failing` otherwise.
    /// - Throws: never, for this deterministic evaluator; `throws` is
    ///   `EvaluatorProtocol`'s requirement on `metrics(subject:input:)`.
    public func metrics(subject: AgentSubject, input: ModelSample<String>) async throws -> [Metric] {
        let metric = Metric(AgentMetricName.calledExpectedTools)
        let invoked = TranscriptAnalyzer.invokedToolPaths(in: subject.steps)
        return [
            invoked == subject.expectation.expectedToolPaths
                ? metric.passing(rationale: "invoked exactly \(subject.expectation.expectedToolPaths.sorted()).")
                : metric.failing(
                    rationale: "invoked \(invoked.sorted()), expected \(subject.expectation.expectedToolPaths.sorted())."
                )
        ]
    }
}

/// plan.md's `Metric("RepairedWithinN")` — passing when the run used at
/// most `AgentScenarioExpectation.maxRunCodeStepsBeforeFinal` `.runCode`
/// steps before either reaching `.final` or exhausting its steps
/// (`TranscriptAnalyzer.runCodeStepsBeforeFinal(in:)`), failing otherwise —
/// deterministic, no judge model needed.
public struct RepairedWithinNEvaluator: EvaluatorProtocol, Sendable {
    /// The evaluated sample type — `Evaluations.EvaluatorProtocol`'s `Input` requirement.
    public typealias Input = ModelSample<String>
    /// The evaluated subject type — `Evaluations.EvaluatorProtocol`'s `Subject` requirement.
    public typealias Subject = AgentSubject

    /// Creates the evaluator.
    ///
    /// See `SearchedThenCalledEvaluator.init()`.
    public init() {}

    /// Grades `subject.steps` against `AgentMetricName.repairedWithinN`,
    /// returning one passing or failing metric.
    ///
    /// - Parameters:
    ///   - subject: the completed run being graded; its `steps` and
    ///     `expectation.maxRunCodeStepsBeforeFinal` supply everything this
    ///     evaluator needs.
    ///   - input: the sample `subject` was resolved from — unused here,
    ///     since all grading data travels on `subject` rather than `input`.
    /// - Returns: a single-element array holding one `Metric` for
    ///   `AgentMetricName.repairedWithinN`: `.passing` if the run used at
    ///   most `maxRunCodeStepsBeforeFinal` `.runCode` steps before either
    ///   reaching `.final` or exhausting `subject.steps` (see
    ///   `TranscriptAnalyzer.runCodeStepsBeforeFinal(in:)`), `.failing`
    ///   otherwise.
    /// - Throws: never, for this deterministic evaluator; `throws` is
    ///   `EvaluatorProtocol`'s requirement on `metrics(subject:input:)`.
    public func metrics(subject: AgentSubject, input: ModelSample<String>) async throws -> [Metric] {
        let metric = Metric(AgentMetricName.repairedWithinN)
        let attempts = TranscriptAnalyzer.runCodeStepsBeforeFinal(in: subject.steps)
        let bound = subject.expectation.maxRunCodeStepsBeforeFinal
        return [
            attempts <= bound
                ? metric.passing(rationale: "used \(attempts) of \(bound) allowed runCode attempt(s).")
                : metric.failing(rationale: "took \(attempts) runCode attempt(s), exceeding the bound of \(bound).")
        ]
    }
}
