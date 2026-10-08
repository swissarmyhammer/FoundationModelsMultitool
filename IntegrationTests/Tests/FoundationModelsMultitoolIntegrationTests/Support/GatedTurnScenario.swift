import Foundation
import FoundationModels
import ScenarioGrading

@testable import FoundationModelsMultitool

/// The conditions that one gated turn is graded on, and the `RESULT` line
/// that it prints.
struct GatedTurnReading {

    /// Each condition, in reporting order, for `grade(scenario:checks:)`.
    let checks: [ScenarioCheck]

    /// The reading to print after the scenario label. It holds the model
    /// scores, and no test asserts them.
    let resultLine: String
}

/// Runs one gated scenario of one turn on the live Router path.
///
/// The steps are the same for each suite that sends one prompt to a mounted
/// session (`GitScenarioTests`, `EnvironmentScenarioTests`,
/// `WebResearchScenarioTests`, and `OperationToolLiveTests`):
///
/// 1. Resolve a live fixture through `withLiveRouterFixture`. When the live
///    path is not wired, that function prints the skip note.
/// 2. Mount `tools` on the session of the resolved `.standard` slot, with no
///    instructions, for the reason that `runNativeIntegrationScenario` gives:
///    the mounted tools are the whole product surface.
/// 3. Stream one turn of `prompt`, and measure how long it takes.
/// 4. Grade the conditions of `reading`, then print its `RESULT` line.
///
/// - Parameters:
///   - name: The scenario label of the skip note, the `SCENARIO` line, and the
///     `RESULT` line.
///   - prompt: The request that the model gets.
///   - makeTools: Makes the session tools from the resolved fixture.
///   - reading: Gives the conditions and the `RESULT` line from the turn and
///     from how long the turn took, in seconds.
/// - Throws: What `withLiveRouterFixture`, `makeTools`, or `streamTurn`
///   throws.
func runGatedTurnScenario(
    named name: String,
    prompt: String,
    tools makeTools: (LiveRouterFixture) throws -> [any Tool],
    reading: (StreamedTurn, TimeInterval) async -> GatedTurnReading
) async throws {
    try await withLiveRouterFixture(name: name) { fixture in
        let session = fixture.profile.standard.makeSession(
            tools: try makeTools(fixture),
            discoveryPriming: scenarioDiscoveryPriming
        )

        let start = Date()
        let turn = try await streamTurn(of: session, prompt: prompt)
        let elapsed = Date().timeIntervalSince(start)

        let result = await reading(turn, elapsed)
        grade(scenario: name, checks: result.checks)
        reportGatedResult(scenario: name, line: result.resultLine)
    }
}

/// Makes the session tools of `registry` with the discovery seams of
/// `fixture`: the same call that a Router host makes.
///
/// No `sampleModel:` value comes from this harness. The seams carry none,
/// thus the product ships without one and this harness must also.
///
/// - Parameters:
///   - registry: The registry to mount.
///   - fixture: The resolved live fixture whose `.flash` slot backs the
///     selection tier.
/// - Returns: The tools to register with the session.
/// - Throws: What
///   `MultiTool.Registry.makeSessionTools(selection:embedder:sampleModel:)`
///   throws.
func makeSessionTools(of registry: MultiTool.Registry, on fixture: LiveRouterFixture) throws -> [any Tool] {
    let seams = fixture.discoverySeams
    return try registry.makeSessionTools(
        selection: seams.selection, embedder: seams.embedder, sampleModel: seams.sampleModel)
}

/// The condition that the `runCode` snippets of a turn called each verb of
/// `verbPaths`.
///
/// The record is `StreamedTurn.calls`, read through
/// `NativeTranscript.typedToolPaths(in:)`. `ScenarioCallLog` is not the
/// record, because it holds the calls of fixture tools only, and a product
/// verb is not a fixture tool.
///
/// - Parameters:
///   - name: The label of the check on the `SCENARIO` line.
///   - verbPaths: The snippet call path of each verb that the snippets must
///     call, without the `tools.` prefix.
///   - turn: The streamed turn, with each session tool call that it made.
/// - Returns: The condition, for `grade(scenario:checks:)`.
func calledTheVerbsCheck(named name: String, verbPaths: Set<String>, in turn: StreamedTurn) -> ScenarioCheck {
    let typedPaths = NativeTranscript.typedToolPaths(in: turn.calls)
    return ScenarioCheck(
        name: name,
        held: verbPaths.isSubset(of: typedPaths),
        failureMessage:
            "expected the \(MultiTool.runCodePath) snippets to call \(verbPaths.sorted()), "
            + "but they called \(typedPaths.sorted()) and the calls were \(turn.calls.map(\.name))"
    )
}

extension ScenarioCheck {

    /// The text of a `correction` field with a value, in a JSON output. A
    /// `null` correction does not agree with it.
    ///
    /// Computed, because `Regex` is not `Sendable` and a stored static value
    /// must be.
    private static var correctionField: Regex<Substring> { #/"correction"\s*:\s*"/# }

    /// The condition that no `runCode` output of a turn holds a
    /// `correction`.
    ///
    /// A correction is the in-band answer of a verb that could not answer.
    /// Thus an output with one shows a verb that refused the call.
    ///
    /// - Parameters:
    ///   - name: The label of the check on the `SCENARIO` line.
    ///   - turn: The streamed turn, with each session tool call that it made.
    /// - Returns: The condition, for `grade(scenario:checks:)`.
    static func noCorrection(named name: String, in turn: StreamedTurn) -> ScenarioCheck {
        let correctedOutputs = turn.calls
            .filter { $0.name == MultiTool.runCodePath }
            .compactMap(\.output)
            .filter { $0.contains(correctionField) }
        return ScenarioCheck(
            name: name,
            held: correctedOutputs.isEmpty,
            failureMessage: "expected no correction in a \(MultiTool.runCodePath) output, but got: "
                + correctedOutputs.joined(separator: " | ")
        )
    }
}

/// The start of a `RESULT` line: how long the turn took and which session
/// tools it called.
///
/// - Parameters:
///   - turn: The streamed turn.
///   - elapsed: How long the turn took, in seconds.
/// - Returns: The reading, with a space at the end.
private func routeReading(of turn: StreamedTurn, elapsed: TimeInterval) -> String {
    "elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) calls=\(turn.calls.map(\.name)) "
}

/// The `RESULT` line of a gated turn: the route, the readings of the scenario,
/// then the start of the reply.
///
/// Each suite that uses `runGatedTurnScenario(named:prompt:tools:reading:)`
/// prints its line through this function. Thus the route and the reply have
/// one format, and each suite gives only the fields that are special to it.
///
/// - Parameters:
///   - turn: The streamed turn.
///   - elapsed: How long the turn took, in seconds.
///   - readings: The fields of the scenario, in print order, each as
///     `name=value`. The line puts one space after each field.
///   - replyPreviewCharacters: How many characters of the reply the line
///     shows.
/// - Returns: The reading to print after the scenario label.
func gatedResultLine(
    of turn: StreamedTurn,
    elapsed: TimeInterval,
    readings: [String],
    replyPreviewCharacters: Int
) -> String {
    let fields = readings.map { $0 + " " }.joined()
    let reply = "reply=\"\(turn.answer.prefix(replyPreviewCharacters))\""
    return routeReading(of: turn, elapsed: elapsed) + fields + reply
}

/// The field of a `RESULT` line that names each verb that the `runCode`
/// snippets of the turn called, without the `tools.` prefix.
///
/// - Parameter turn: The streamed turn.
/// - Returns: The field, as `typed=[...]`, in sorted order.
func typedPathsReading(of turn: StreamedTurn) -> String {
    "typed=\(NativeTranscript.typedToolPaths(in: turn.calls).sorted())"
}

/// The field of a `RESULT` line that tells if the discovery priming of the
/// turn ran.
///
/// - Parameter turn: The streamed turn.
/// - Returns: The field, as `priming=<label>`, with the label of
///   `primingLabel(_:)`.
func primingReading(of turn: StreamedTurn) -> String {
    "priming=\(primingLabel(turn))"
}

/// The field of a `RESULT` line that names each tool call of the turn that
/// failed.
///
/// - Parameter turn: The streamed turn.
/// - Returns: The field, as `failedCalls=[...]`.
func failedCallsReading(of turn: StreamedTurn) -> String {
    "failedCalls=\(turn.failedCalls)"
}
