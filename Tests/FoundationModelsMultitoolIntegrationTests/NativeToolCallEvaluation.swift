import Testing

import Evaluations
import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool
@testable import multitool_cli

/// The successor to the retired `AgentEvaluation.swift` (task `k4mj1gm`
/// deleted it porting the gated suite to the native `LanguageModelSession`
/// design; this task, `twvq4mw`, was filed to investigate whether it could
/// be rebuilt against the new transcript shape). It could: unlike
/// `MultiToolAgent`'s hand-rolled Router transcript, a native
/// `LanguageModelSession`'s own `FoundationModels.Transcript` is exactly
/// what Apple's `Evaluations` framework's tool-calling machinery is built to
/// grade.
///
/// **Verified against the shipping SDK's `.swiftinterface`** (the same
/// approach the retired file's own doc comment used —
/// `Evaluations.framework`'s `Evaluations.swiftmodule/*.swiftinterface`
/// under `xcrun --show-sdk-path`'s toolchain), not guessed from plan.md:
///
/// - **The conversion is free.** `FoundationModels.Transcript` gets a
///   `structuredTranscript: Evaluations.StructuredTranscript` computed
///   property directly from the `Evaluations` module (an `extension
///   FoundationModels.Transcript`) — no adapter to write. `session
///   .transcript.structuredTranscript` is all `subject(from:)` below needs.
/// - **`Evaluations.ToolCallEvaluator<Input>`** requires `Input
///   .Expectation == Evaluations.TrajectoryExpectation` and grades a fixed
///   `Evaluations.ModelSubject<Input.ExpectedValue>` (not a custom `Subject`
///   conformer like the retired file's `AgentSubject` — the framework's own
///   `ModelSubject` already carries a `transcript: StructuredTranscript?`),
///   comparing `subject.toolCalls` (i.e. `structuredTranscript.toolCalls`,
///   every recorded `FoundationModels.Transcript.ToolCall`) against an
///   `ordered`/`unordered`/`disallowed` list of `Evaluations.ToolExpectation`
///   entries, each matched by tool name plus, optionally,
///   `Evaluations.ArgumentMatcher`s over that call's arguments.
///
/// **What generalizes, and what doesn't.** The native design registers
/// exactly two top-level tools with the session — `findAPIsTool` and
/// `multiTool` (`"findAPIs"`/`"runCode"`) — so every `Transcript.ToolCall`
/// `ToolCallEvaluator` sees names one of those two. Mapped against the
/// retired suite's three metrics (`AgentEvaluators.swift`'s
/// `AgentMetricName`):
///
/// - **`SearchedThenCalled`** (a `findAPIs` call precedes the first
///   `runCode` call) generalizes cleanly: `TrajectoryExpectation(ordered:
///   [ToolExpectation("findAPIs"), ToolExpectation("runCode")])` is exactly
///   an ordering constraint over those two top-level tool names.
/// - **`CalledExpectedTools`** *partially* generalizes. `ArgumentMatcher`
///   actually has nine cases, not just `.exact`/`.keyOnly`/`.oneOf`/`.range`
///   — it also has `.pattern(argumentName:regex:)` and
///   `.contains(argumentName:substring:)` (plus `.hasPrefix`/`.hasSuffix`/
///   `.naturalLanguage`), so a `runCode` `ToolExpectation` *can* assert that
///   its `code` argument contains a `tools.<path>(` call site —
///   `runCodeExpectation(invoking:)` below does exactly that, for every
///   scenario's expected `tools.*` paths. What it can't express: the
///   retired `CalledExpectedToolsEvaluator`'s *exact-set* check (`invoked ==
///   expectedToolPaths`, no more, no fewer) — there is no "argument does
///   NOT contain" / "only these calls appear" primitive on
///   `ArgumentMatcher`/`TrajectoryExpectation`, only positive presence
///   matchers. So this suite ports the presence half (every expected path
///   was referenced) and leaves the exclusivity half to
///   `SearchThenCallTests`' own `NativeTranscript.invokedToolPaths(in:)`
///   set-equality `#expect`, which stays exactly as capable as before.
/// - **`RepairedWithinN`** does NOT generalize: it grades a call-count
///   *ceiling* (at most N `runCode` calls before `.final`).
///   `TrajectoryExpectation`'s `ordered`/`unordered`/`disallowed` are
///   presence/order lists and `allowsAdditionalCalls` is a single boolean —
///   none of that expresses "at most N" for a specific tool. This stays
///   `SearchThenCallTests`' own per-scenario `#expect`
///   (`NativeTranscript.toolCallCount(in:named:)`).
///
/// So this suite grades an ordering property cleanly and a tool-path
/// presence property partially, via the framework's built-in evaluator,
/// across repeated live samples with mean/stddev aggregation (the
/// `Evaluations` framework's whole point, and the statistical payoff the
/// one-shot `#expect`-based `SearchThenCallTests` doesn't give). The
/// exact-set and call-count properties are not a regression — per this
/// suite's own scope note (task `twvq4mw`), they're already covered by
/// `SearchThenCallTests` without this port.
///
/// **Known gap vs. `Support/ScenarioRunner.swift`.** `runNativeIntegrationScenario`
/// explicitly catches `GenerationError.notWiredForLiveInference` around both
/// `LiveRouterFixture.resolve()` and the session-driving body, treating it
/// as a clean skip — because `.enabled(if: multitoolIntegrationEnabled)`
/// only gates on the `MULTITOOL_INTEGRATION` env var, a distinct condition
/// from whether live inference is actually wired on the box running it.
/// `subject(from:)` below does not catch it (matching the retired
/// `AgentEvaluation.swift`'s own `subject(from:)`, which had the identical
/// gap): the `Evaluations.Evaluation` protocol gives `subject(from:)` no
/// per-sample "skip" signal short of throwing, so on a machine where the
/// env var is set but live inference isn't wired, this suite fails loudly
/// instead of skipping cleanly like `SearchThenCallTests`/`PrefixReuseTests`
/// do. Not fixed here — flagged as a real, inherited limitation rather than
/// silently mirrored.
struct NativeToolCallEvaluation: Evaluation {
    typealias Sample = ModelSample<String>
    typealias Subject = ModelSubject<String>
    typealias SampleLoader = ArrayLoader<ModelSample<String>>

    /// One sample MultiTool scenario: the prompt to drive a native
    /// `LanguageModelSession(tools: [multiTool, findAPIsTool])` with, the
    /// tool set to wrap, and the trajectory `ToolCallEvaluator` grades the
    /// resulting transcript against.
    private struct Scenario {
        let prompt: String
        let tools: [any Tool]
        let expectation: TrajectoryExpectation
    }

    /// Builds a `"runCode"` `ToolExpectation` asserting its `code` argument
    /// references every one of `toolPaths` — the presence half of the
    /// retired `CalledExpectedToolsEvaluator`'s check (see this type's own
    /// documentation above for what's deliberately not ported).
    ///
    /// - Parameter toolPaths: the `tools.*` call paths the `runCode` call's
    ///   snippet is expected to reference. Sorted before building matchers
    ///   so the resulting `ToolExpectation` is deterministic across runs.
    /// - Returns: a `ToolExpectation("runCode", ...)` with one
    ///   `.contains(argumentName: "code", substring:)` matcher per path.
    private static func runCodeExpectation(invoking toolPaths: Set<String>) -> ToolExpectation {
        ToolExpectation(
            "runCode",
            arguments: toolPaths.sorted().map { .contains(argumentName: "code", substring: "tools.\($0)(") }
        )
    }

    /// Reuses `SearchThenCallTests`' own four scenarios (tool sets, prompts,
    /// and expected `tools.*` paths verbatim) as this evaluation's dataset.
    /// Scenario 3's prompt is deliberately reworded from `SearchThenCallTests`'
    /// own text (which is identical to scenario 2's — fine for two
    /// independent `@Test` funcs but not here) — `subject(from:)` looks a
    /// scenario up by its sample's prompt, so every scenario's prompt text
    /// must be unique; same fix the retired `AgentEvaluation.swift` applied
    /// for the same reason.
    private static let scenarios: [Scenario] = [
        // Scenario 1: single-call `weather`.
        Scenario(
            prompt: "How warm is it in Austin right now?",
            tools: [IntegrationWeatherTool()],
            expectation: TrajectoryExpectation(
                ordered: [ToolExpectation("findAPIs"), runCodeExpectation(invoking: ["weather"])]
            )
        ),
        // Scenario 2: compose/chain tripCities -> weather -> warmest.
        Scenario(
            prompt: "Of the cities on my trip, which is warmest right now?",
            tools: [IntegrationTripCitiesTool(), IntegrationWeatherTool()],
            expectation: TrajectoryExpectation(
                ordered: [ToolExpectation("findAPIs"), runCodeExpectation(invoking: ["tripCities", "weather"])]
            )
        ),
        // Scenario 3: discovery under ~20 distractors. Reworded prompt — see
        // this property's own documentation above.
        Scenario(
            prompt: "Of all the trip-planning tools available, which city on my trip is warmest right now?",
            tools: [IntegrationWeatherTool(), IntegrationTripCitiesTool()] + integrationDistractorTools,
            expectation: TrajectoryExpectation(
                ordered: [ToolExpectation("findAPIs"), runCodeExpectation(invoking: ["tripCities", "weather"])]
            )
        ),
        // Scenario 4: repair from a trip-prone tool. The retired suite's
        // `expectFindAPIs: false` means no ordering claim was ever made for
        // this scenario, so `unordered` (rather than `ordered`) is the right
        // shape — it does NOT additionally assert that `findAPIs` was *not*
        // called (that would need an explicit `disallowed:` entry, which
        // this scenario deliberately omits, mirroring the retired
        // evaluator's own `.ignore`-not-`.failing` treatment of
        // `expectFindAPIs == false`). The retired `RepairedWithinN`
        // call-count bound has no `TrajectoryExpectation` equivalent (see
        // this type's own documentation above).
        Scenario(
            prompt: "Confirm my booking, id 42.",
            tools: [IntegrationBookingTool()],
            expectation: TrajectoryExpectation(unordered: [runCodeExpectation(invoking: ["book"])])
        ),
    ]

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Self.scenarios.map { ModelSample(prompt: $0.prompt, expectations: $0.expectation) })
    }

    /// Runs one scenario's prompt through a freshly-resolved live, native
    /// `LanguageModelSession(tools: [multiTool, findAPIsTool])`, then reduces
    /// the resulting `FoundationModels.Transcript` to a `ModelSubject` the
    /// framework's own `ToolCallEvaluator` grades — the same construction
    /// `runNativeIntegrationScenario` (`Support/ScenarioRunner.swift`) uses,
    /// with a fresh `LiveRouterFixture` per scenario (never shared across
    /// samples), so each subject's transcript reflects only that scenario's
    /// own run.
    ///
    /// - Parameter sample: the dataset sample to run.
    /// - Returns: the subject `evaluators` grades.
    /// - Throws: `GenerationError.notWiredForLiveInference` if the Router's
    ///   live decode path isn't wired up in this environment (see this
    ///   type's own documentation above — unlike `runNativeIntegrationScenario`,
    ///   this is not caught as a skip here); a
    ///   `NativeToolCallEvaluationError.unknownScenario` if `sample`'s
    ///   prompt doesn't match any entry in `scenarios` (an invariant
    ///   violation of this evaluation's own wiring, since `dataset` is
    ///   derived from the same `scenarios` list); or whatever running the
    ///   session itself throws.
    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        guard let scenario = Self.scenarios.first(where: { $0.prompt == sample.promptDescription }) else {
            throw NativeToolCallEvaluationError.unknownScenario(prompt: sample.promptDescription)
        }

        let fixture = try await LiveRouterFixture.resolve()
        do {
            let registry = try MultiTool.Builder().addTools(scenario.tools).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            let findAPIsTool = try FindAPIsTool(registry: registry, librarian: fixture.profile.flash)
            let mlxModel = CLIRunner.makeMLXLanguageModel(for: fixture.profile.standard)
            let session = LanguageModelSession(
                model: mlxModel,
                tools: [multiTool, findAPIsTool],
                instructions: "You are a helpful assistant. Use runCode to get things done."
            )
            let response = try await session.respond(to: scenario.prompt)
            let subject = ModelSubject(value: response.content, transcript: session.transcript.structuredTranscript)
            await fixture.tearDown()
            return subject
        } catch {
            await fixture.tearDown()
            throw error
        }
    }

    @EvaluatorsBuilder<Sample, Subject> var evaluators: Evaluators {
        ToolCallEvaluator<Sample>(
            allPass: Metric(NativeToolCallMetricName.allToolCallsPass),
            percentagePass: Metric(NativeToolCallMetricName.percentageToolCallsPass)
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Metric(NativeToolCallMetricName.allToolCallsPass))
        aggregator.computeStandardDeviation(of: Metric(NativeToolCallMetricName.allToolCallsPass))
        aggregator.computeMean(of: Metric(NativeToolCallMetricName.percentageToolCallsPass))
        aggregator.computeStandardDeviation(of: Metric(NativeToolCallMetricName.percentageToolCallsPass))
    }
}

/// `Evaluations.ToolCallEvaluator`'s two metric names, graded per sample
/// against `NativeToolCallEvaluation`'s `TrajectoryExpectation`s —
/// `allPass` (did every expected call match) and `percentagePass` (what
/// fraction did). Named constants (not repeated string literals), mirroring
/// `AgentEvaluators.swift`'s `AgentMetricName`.
enum NativeToolCallMetricName {
    /// `Evaluations.ToolCallEvaluator`'s `allPass` metric: passing only when
    /// every expected tool call in the sample's `TrajectoryExpectation`
    /// matched.
    static let allToolCallsPass = "AllNativeToolCallsPass"
    /// `Evaluations.ToolCallEvaluator`'s `percentagePass` metric: the
    /// fraction of the sample's expected tool calls that matched.
    static let percentageToolCallsPass = "PercentageNativeToolCallsPass"
}

/// A failure specific to `NativeToolCallEvaluation`'s own dataset/subject
/// wiring — never expected in practice since `dataset` and `subject(from:)`
/// are both derived from the same `NativeToolCallEvaluation.scenarios` list.
enum NativeToolCallEvaluationError: Error, CustomStringConvertible {
    /// `subject(from:)` received a sample whose prompt matches no entry in
    /// `NativeToolCallEvaluation.scenarios`.
    case unknownScenario(prompt: String)

    var description: String {
        switch self {
        case .unknownScenario(let prompt):
            return "NativeToolCallEvaluation: no scenario registered for prompt \"\(prompt)\"."
        }
    }
}

/// `twvq4mw`'s gated eval suite: the same `MULTITOOL_INTEGRATION` opt-in env
/// var as `SearchThenCallTests`/`PrefixReuseTests` — unset (the default),
/// `.enabled(if:)` skips the whole suite before `.evaluates(...)` ever
/// invokes `NativeToolCallEvaluation.subject(from:)`, so `swift test` stays
/// green with zero downloads and zero live inference.
///
/// `.timeLimit(.minutes(60))`: a real-hardware run of this suite resolves
/// four fresh `LiveRouterFixture`s in sequence (one per scenario, per
/// `subject(from:)`'s own documentation) — each a real model load plus a
/// live generation, the same per-scenario cost `SearchThenCallTests`/
/// `IntegrationGate.swift` document taking up to several minutes apiece on
/// the pinned tiny model, more on the ~20-distractor scenario. An initial
/// real-hardware attempt at `.minutes(30)` (this suite's first-drafted
/// limit) hit that wall before any sample finished, recorded on task
/// `twvq4mw`; `.minutes(60)` gives a full run more headroom.
@Suite(
    "Evaluations-framework eval suite grading native tool-call trajectories (twvq4mw)",
    .enabled(if: multitoolIntegrationEnabled),
    .timeLimit(.minutes(60))
)
struct NativeToolCallEvaluationTests {
    /// The mean-aggregate pass threshold — mirrors the retired
    /// `AgentEvaluationTests.passThreshold`.
    private static let passThreshold = 0.9

    @Test(.evaluates(NativeToolCallEvaluation(), info: ["suite": "twvq4mw"]))
    func nativeToolCallEvaluation() throws {
        let result = EvaluationContext.current.result
        #expect(
            result.aggregateValue(.mean(of: Metric(NativeToolCallMetricName.allToolCallsPass))) >= Self.passThreshold,
            "AllNativeToolCallsPass mean below threshold:\n\(result.groupedSummary)"
        )
    }
}
