import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The gated scenario that proves that a real model reads a repository through
/// the git capability (task `^xd2dbd1`, git.md § "Proposed order of the
/// tasks", item 11).
///
/// **The mount.** `MultiTool.Builder().withGit(root:)` over the work folder of
/// ``GitScenarioHistory``, vended through `makeSessionTools(of:on:)` and
/// mounted by `runGatedTurnScenario(named:prompt:tools:reading:)` on the
/// `RoutedSession` that the resolved `.standard` slot vends. This is the
/// wiring that a Router host makes, the same as `WebResearchScenarioTests`.
/// The session gets no instructions: the tool descriptions are the whole
/// product surface.
///
/// **The scenario.** One short prompt, thus one model turn (task `^k6wzrxn`):
/// the diff of the function that the work folder renames. Each model turn
/// costs approximately 100 s on the CI runner, and the CI integration job must
/// stay in 20 minutes. The unit tests of each verb call each verb without a
/// model, and `GitGoalSnippetTests` runs the goal snippet of git.md word for
/// word. The scenario runs one time on each push. There is no skip and no
/// second round.
///
/// **The grade asserts code properties only** (the user's rule: a test does
/// not assert a fixed model score):
///
/// 1. A `runCode` snippet of the turn called `git.diff`. The record is
///    `StreamedTurn.calls`, read through `NativeTranscript.typedToolPaths(in:)`.
/// 2. No `runCode` output holds a `correction`. A correction is the in-band
///    answer of a verb that could not answer, thus an output with one shows a
///    verb that refused the call.
///
/// The `RESULT` line prints how many facts of the repository the answer
/// names. That count measures the model, thus no test asserts it.
@Suite(
    "Gated git scenarios: a real model reads a repository through tools.git in runCode",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct GitScenarioTests {

    /// The label that the result line carries.
    private static let scenarioName = "gitRenamedFunctionDiff"

    /// The request that the model gets.
    ///
    /// "Semantic diff" is the term of the `git.diff` description. A local run
    /// with "compare the file at HEAD with the file in the work folder" took
    /// 171 s: the model looked for a file reader that the git mount does not
    /// have, and called `git.diff` only after six other calls.
    ///
    /// "One short sentence" keeps the answer as long as the printed score
    /// needs and no longer: each generated token costs approximately 0.2 s on
    /// the CI runner `mini`, and the whole suite must stay in 20 minutes. The
    /// first local run of this suite, with no such request, gave a reply of
    /// several lines.
    private static let prompt = "In the git repository, give the semantic diff of \(GitScenarioHistory.geometryPath) "
        + "between HEAD and the work folder. Which function has a new name, and what is the new name? "
        + "Answer in one short sentence."

    /// The snippet call path of each verb that the snippets must call,
    /// without the `tools.` prefix.
    private static let verbPaths: Set<String> = ["git.diff"]

    /// The facts that a correct answer names. The `RESULT` line prints the
    /// count; no test asserts it.
    private static let answerFacts = [GitScenarioHistory.functionName, GitScenarioHistory.renamedFunctionName]

    /// How many characters of the reply the `RESULT` line shows.
    private static let replyPreviewCharacters = 160

    /// The label of the check that the snippets called each verb.
    private static let calledTheVerbsCheckName = "calledTheVerbs"

    /// The label of the check that no `runCode` output holds a correction.
    private static let noCorrectionCheckName = "noCorrection"

    @Test("the model diffs the renamed function from a snippet, and no verb answers a correction")
    func theModelDiffsTheRenamedFunction() async throws {
        let repository = try GitScenarioHistory.make()
        let registry = try MultiTool.Builder().withGit(root: repository.workDirectory).buildRegistry()
        // The release of `repository` removes its work folder, thus the
        // repository must live until the turn ends.
        defer { withExtendedLifetime(repository) {} }
        try await runGatedTurnScenario(
            named: Self.scenarioName,
            prompt: Self.prompt,
            tools: { try makeSessionTools(of: registry, on: $0) },
            reading: { turn, elapsed in
                GatedTurnReading(
                    checks: Self.checks(turn: turn),
                    resultLine: gatedResultLine(
                        of: turn,
                        elapsed: elapsed,
                        readings: Self.readings(of: turn),
                        replyPreviewCharacters: Self.replyPreviewCharacters))
            })
    }

    /// The conditions that the scenario is graded on: the verbs, then the
    /// corrections.
    ///
    /// - Parameter turn: The streamed turn, with each session tool call it
    ///   made.
    /// - Returns: Each condition, for `grade(scenario:checks:)`.
    private static func checks(turn: StreamedTurn) -> [ScenarioCheck] {
        [
            calledTheVerbsCheck(named: calledTheVerbsCheckName, verbPaths: verbPaths, in: turn),
            ScenarioCheck.noCorrection(named: noCorrectionCheckName, in: turn),
        ]
    }

    /// The fields of the `RESULT` line that this scenario gives to
    /// `gatedResultLine(of:elapsed:readings:replyPreviewCharacters:)`: the
    /// token usage, the snippet verbs, the score, the priming, and the failed
    /// calls.
    ///
    /// - Parameter turn: The streamed turn.
    /// - Returns: The fields, in print order.
    private static func readings(of turn: StreamedTurn) -> [String] {
        let namedFacts = answerFacts.filter { turn.answer.localizedCaseInsensitiveContains($0) }
        let score = "answerFacts=\(namedFacts.count)/\(answerFacts.count) named=\(namedFacts)"
        return [
            "tokens=\(turn.tokenUsage ?? "n/a")",
            typedPathsReading(of: turn),
            score,
            primingReading(of: turn),
            failedCallsReading(of: turn),
        ]
    }
}
