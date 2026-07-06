import Foundation
import Testing

import Evaluations
import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// M6.5b's ungated proof of "the evaluator + threshold-gate logic":
/// plan.md's `Metric`/`EvaluatorProtocol`/`MetricsAggregator`/
/// `EvaluationResult.aggregateValue(_:)` machinery, exercised against
/// checked-in fixture transcripts (M6.5a's `Goldens/*.jsonl`, the same
/// fixtures `TranscriptAssertionTests` parses) and synthetic step arrays —
/// never a live Router/model, so this runs in normal CI, unlike the gated
/// `AgentEvaluation` (`Tests/FoundationModelsMultitoolIntegrationTests/AgentEvaluation.swift`)
/// this suite otherwise mirrors one-for-one: same `Evaluations.Evaluation`
/// protocol, same `SearchedThenCalledEvaluator`/`CalledExpectedToolsEvaluator`/
/// `RepairedWithinNEvaluator` conformers (`Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift`),
/// same aggregation/gate expression — only `subject(from:)` differs (a pure
/// fixture replay here, a live `MultiToolAgent.respond(to:)` call there).
///
/// Acceptance criterion this suite closes: "fixture metric values below the
/// threshold make the gate expression evaluate false, above make it true —
/// no one-time manual inversion ritual." `meanAggregateGateFlipsAcrossThreshold`
/// below is that literal proof, run twice (once with an all-failing fixture
/// dataset, once with an all-passing one) so a future regression that
/// silently inverts the gate comparison is caught by re-running the suite,
/// not by a human re-deriving the expected direction by hand.
@Suite("Evaluator + threshold-gate logic (M6.5b)")
struct EvaluatorGateTests {
    /// The mean-aggregate pass threshold plan.md's own worked gate example
    /// uses (`>= 0.9`) — reused here so this suite proves the exact
    /// comparison the gated suite's `#expect` will perform.
    private static let passThreshold = 0.9

    // MARK: - Fixture loading

    /// Loads a checked-in fixture transcript from `Goldens/<name>` next to
    /// this file — the same `#filePath`-relative, whitelist-validated
    /// pattern `TranscriptAssertionTests.loadFixture(_:)` uses (that type's
    /// own documentation explains why a `name` interpolated into a
    /// filesystem path needs the whitelist guard below).
    ///
    /// - Parameter name: the fixture file's name. Must consist solely of
    ///   letters, digits, `-`, `_`, and `.`, and must not be all dots.
    /// - Returns: the fixture file's raw contents.
    /// - Throws: ``InvalidFixtureNameError`` if `name` fails that check.
    private static func loadFixture(_ name: String) throws -> String {
        let isWhitelisted = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        let isAllDots = name.allSatisfy { $0 == "." }
        guard isWhitelisted, !isAllDots else {
            throw InvalidFixtureNameError(name: name)
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Parses a fixture transcript's main-agent steps — `TranscriptAnalyzer
    /// .steps(in:slot:)` filtered to `.standard`, the same slot
    /// `TranscriptAssertionTests` and the gated `ScenarioRunner` both read.
    ///
    /// - Parameter fixtureName: the fixture file's name under `Goldens/`.
    /// - Returns: the parsed main-agent steps, in recorded order.
    private static func steps(fromFixture fixtureName: String) throws -> [AgentStep] {
        let events = try TranscriptAnalyzer.decodeJsonl(try loadFixture(fixtureName))
        return TranscriptAnalyzer.steps(in: events, slot: .standard)
    }

    // MARK: - SearchedThenCalledEvaluator

    @Test("SearchedThenCalledEvaluator passes for the search-then-call fixture, which searches before calling")
    func searchedThenCalledPassesForSearchThenCallFixture() async throws {
        let subject = AgentSubject(
            value: "Austin is the warmest at 31C.",
            steps: try Self.steps(fromFixture: "SearchThenCallTranscript.jsonl"),
            expectation: AgentScenarioExpectation(expectFindAPIs: true, expectedToolPaths: [], maxRunCodeStepsBeforeFinal: 1)
        )
        let metrics = try await SearchedThenCalledEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.passing])
    }

    @Test("SearchedThenCalledEvaluator fails for the repair fixture when the scenario expects discovery")
    func searchedThenCalledFailsForRepairFixtureWhenExpected() async throws {
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: AgentScenarioExpectation(expectFindAPIs: true, expectedToolPaths: [], maxRunCodeStepsBeforeFinal: 5)
        )
        let metrics = try await SearchedThenCalledEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.failing])
    }

    @Test("SearchedThenCalledEvaluator ignores a scenario that does not expect discovery, rather than failing it")
    func searchedThenCalledIgnoresWhenNotExpected() async throws {
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: AgentScenarioExpectation(expectFindAPIs: false, expectedToolPaths: [], maxRunCodeStepsBeforeFinal: 5)
        )
        let metrics = try await SearchedThenCalledEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.ignore])
    }

    // MARK: - CalledExpectedToolsEvaluator

    @Test("CalledExpectedToolsEvaluator passes when the snippet invoked exactly the expected tools")
    func calledExpectedToolsPassesForExactMatch() async throws {
        let subject = AgentSubject(
            value: "Austin is the warmest at 31C.",
            steps: try Self.steps(fromFixture: "SearchThenCallTranscript.jsonl"),
            expectation: AgentScenarioExpectation(
                expectFindAPIs: true,
                expectedToolPaths: ["tripCities", "weather"],
                maxRunCodeStepsBeforeFinal: 1
            )
        )
        let metrics = try await CalledExpectedToolsEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.passing])
    }

    @Test("CalledExpectedToolsEvaluator fails when the snippet invoked a different tool set than expected")
    func calledExpectedToolsFailsForMismatch() async throws {
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: AgentScenarioExpectation(
                expectFindAPIs: false,
                expectedToolPaths: ["weather"],
                maxRunCodeStepsBeforeFinal: 5
            )
        )
        let metrics = try await CalledExpectedToolsEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.failing])
    }

    // MARK: - RepairedWithinNEvaluator

    @Test("RepairedWithinNEvaluator passes when the repair fixture's two runCode attempts are within the bound")
    func repairedWithinNPassesWithinBound() async throws {
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: AgentScenarioExpectation(expectFindAPIs: false, expectedToolPaths: ["book"], maxRunCodeStepsBeforeFinal: 2)
        )
        let metrics = try await RepairedWithinNEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.passing])
    }

    @Test("RepairedWithinNEvaluator fails when the repair fixture's two runCode attempts exceed a tighter bound")
    func repairedWithinNFailsBeyondBound() async throws {
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: AgentScenarioExpectation(expectFindAPIs: false, expectedToolPaths: ["book"], maxRunCodeStepsBeforeFinal: 1)
        )
        let metrics = try await RepairedWithinNEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.failing])
    }

    @Test("RepairedWithinNEvaluator passes a transcript that never reaches .final, as long as its runCode count is within the bound, without claiming .final was reached")
    func repairedWithinNPassesWithoutReachingFinal() async throws {
        // No `.final` step anywhere — `TranscriptAnalyzer
        // .runCodeStepsBeforeFinal(in:)` falls through its loop and returns
        // the total `.runCode` count, which sits at the bound here. This
        // pins down the chosen contract (reword rather than require
        // `.final`): such a run legitimately passes, and the rationale must
        // not claim `.final` was reached.
        let steps: [AgentStep] = [
            .findAPIs(task: "look up the tool"),
            .runCode(code: "tools.book()"),
        ]
        let subject = AgentSubject(
            value: "Booked the trip.",
            steps: steps,
            expectation: AgentScenarioExpectation(expectFindAPIs: false, expectedToolPaths: ["book"], maxRunCodeStepsBeforeFinal: 1)
        )
        let metrics = try await RepairedWithinNEvaluator().metrics(subject: subject, input: ModelSample(prompt: "x"))
        #expect(metrics.map(\.value) == [.passing])
        #expect(!(metrics.first?.rationale?.contains("final") ?? false), "the passing rationale must not claim .final was reached")
    }

    // MARK: - Threshold gate: fixture metric values flip the gate expression

    /// A tiny, fully offline `Evaluations.Evaluation` used only to prove the
    /// real threshold-gate machinery (`Evaluation.run(info:)`,
    /// `MetricsAggregator`/`AggregationOperation`, `EvaluationResult
    /// .aggregateValue(_:)`) flips correctly around a threshold from
    /// fixture-derived metric values — no live Router/model anywhere in
    /// this type, unlike the gated `AgentEvaluation` this ungated proof
    /// otherwise mirrors. `subject(from:)` is a pure, in-memory lookup
    /// against canned subjects built from checked-in fixture transcripts.
    private struct FixtureGateEvaluation: Evaluation {
        typealias Sample = ModelSample<String>
        typealias Subject = AgentSubject
        typealias SampleLoader = ArrayLoader<ModelSample<String>>

        /// Canned subjects keyed by their sample's prompt text (`ModelSample
        /// .promptDescription`) — every prompt in a given evaluation run
        /// must be unique so `subject(from:)` can look one up unambiguously.
        let subjectsByPrompt: [String: AgentSubject]

        var dataset: ArrayLoader<ModelSample<String>> {
            ArrayLoader(samples: subjectsByPrompt.keys.sorted().map { ModelSample(prompt: $0) })
        }

        func subject(from sample: ModelSample<String>) async throws -> AgentSubject {
            guard let subject = subjectsByPrompt[sample.promptDescription] else {
                throw UnknownFixturePromptError(prompt: sample.promptDescription)
            }
            return subject
        }

        @EvaluatorsBuilder<Sample, Subject> var evaluators: Evaluators {
            SearchedThenCalledEvaluator()
        }

        func aggregateMetrics(using aggregator: inout MetricsAggregator) {
            aggregator.computeMean(of: Metric(AgentMetricName.searchedThenCalled))
        }
    }

    @Test("the mean-aggregate SearchedThenCalled gate is false when every fixture sample fails, and true when every fixture sample passes")
    func meanAggregateGateFlipsAcrossThreshold() async throws {
        // Both fixtures are graded with expectFindAPIs: true, so the
        // repair fixture (which never calls findAPIs at all) is a genuine
        // failing sample here — not the .ignore outcome it would get under
        // its own real scenario configuration (see
        // `searchedThenCalledIgnoresWhenNotExpected` above). That's
        // deliberate: this test needs one guaranteed-failing and one
        // guaranteed-passing fixture-derived subject to prove the gate
        // flips in both directions.
        let expectation = AgentScenarioExpectation(expectFindAPIs: true, expectedToolPaths: [], maxRunCodeStepsBeforeFinal: 5)
        let passingSubject = AgentSubject(
            value: "Austin is the warmest at 31C.",
            steps: try Self.steps(fromFixture: "SearchThenCallTranscript.jsonl"),
            expectation: expectation
        )
        let failingSubject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: expectation
        )

        let allFailing = FixtureGateEvaluation(subjectsByPrompt: [
            "prompt one": failingSubject,
            "prompt two": failingSubject,
        ])
        let failingResult = try await allFailing.run()
        let failingMean = failingResult.aggregateValue(.mean(of: Metric(AgentMetricName.searchedThenCalled)))
        #expect(failingMean < Self.passThreshold, "an all-failing fixture dataset must not clear the gate")

        let allPassing = FixtureGateEvaluation(subjectsByPrompt: [
            "prompt one": passingSubject,
            "prompt two": passingSubject,
        ])
        let passingResult = try await allPassing.run()
        let passingMean = passingResult.aggregateValue(.mean(of: Metric(AgentMetricName.searchedThenCalled)))
        #expect(passingMean >= Self.passThreshold, "an all-passing fixture dataset must clear the gate")

        // The same values feeding the exact `#expect` shape the gated
        // AgentEvaluation test uses, spelled out explicitly so a reviewer
        // can see both directions of the gate side by side.
        #expect(!(failingMean >= Self.passThreshold))
        #expect(passingMean >= Self.passThreshold)
    }

    @Test("a mixed fixture dataset's mean sits strictly between the all-failing and all-passing means")
    func meanAggregateGateReflectsAMixedDataset() async throws {
        let expectation = AgentScenarioExpectation(expectFindAPIs: true, expectedToolPaths: [], maxRunCodeStepsBeforeFinal: 5)
        let passingSubject = AgentSubject(
            value: "Austin is the warmest at 31C.",
            steps: try Self.steps(fromFixture: "SearchThenCallTranscript.jsonl"),
            expectation: expectation
        )
        let failingSubject = AgentSubject(
            value: "Booked the trip.",
            steps: try Self.steps(fromFixture: "RepairTranscript.jsonl"),
            expectation: expectation
        )

        let mixed = FixtureGateEvaluation(subjectsByPrompt: [
            "prompt one": passingSubject,
            "prompt two": failingSubject,
        ])
        let mixedResult = try await mixed.run()
        let mixedMean = mixedResult.aggregateValue(.mean(of: Metric(AgentMetricName.searchedThenCalled)))

        #expect(mixedMean == 0.5)
        #expect(mixedMean < Self.passThreshold, "a half-passing dataset must not clear a 0.9 gate")
    }
}

/// A fixture `name` passed to `EvaluatorGateTests.loadFixture(_:)` that
/// failed the letters/digits/`-`/`_`/`.` whitelist check — guards against
/// the name being used to construct a path outside `Goldens/`. Mirrors
/// `TranscriptAssertionTests`'s own `InvalidFixtureNameError` (a distinct
/// type here since that one is file-private to its own suite).
private struct InvalidFixtureNameError: Error, CustomStringConvertible {
    let name: String
    var description: String { "invalid fixture name: \(name)" }
}

/// Thrown by `EvaluatorGateTests.FixtureGateEvaluation.subject(from:)` when
/// a sample's prompt has no canned subject registered — an invariant
/// violation of this test-only fixture wiring, never expected to actually
/// throw given `dataset` is derived from the very same `subjectsByPrompt`
/// dictionary `subject(from:)` looks up.
private struct UnknownFixturePromptError: Error, CustomStringConvertible {
    let prompt: String
    var description: String { "no canned fixture subject registered for prompt \"\(prompt)\"" }
}
