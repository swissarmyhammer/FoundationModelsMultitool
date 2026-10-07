import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The gated scenarios that prove that a real model reads a repository through
/// the git capability (task `^xd2dbd1`, git.md § "Proposed order of the
/// tasks", item 11).
///
/// **The mount.** `MultiTool.Builder().withGit(root:)` over the work folder of
/// ``GitScenarioHistory``, vended through
/// `MultiTool.Registry.makeSessionTools(selection:embedder:)` and mounted on
/// the `RoutedSession` that the resolved `.standard` slot vends. This is the
/// wiring that a Router host makes, the same as `WebResearchScenarioTests`.
/// The session gets no instructions: the tool descriptions are the whole
/// product surface.
///
/// **The scenarios.** One prompt for each scenario of the card: the goal of
/// git.md (the changed files and their diff), `status`, `log`, `show`,
/// `blame`, and a `diff` of a renamed function. Each scenario runs one time on
/// each push. There is no skip and no second round.
///
/// **The grade asserts code properties only** (the user's rule: a test does
/// not assert a fixed model score):
///
/// 1. A `runCode` snippet of the turn called each verb that the scenario
///    names. The record is `StreamedTurn.calls`, read through
///    `NativeTranscript.typedToolPaths(in:)`.
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

    /// One prompt, the verbs that its snippets must call, and the facts that a
    /// correct answer names.
    struct GitScenario: Sendable, CustomTestStringConvertible {

        /// The label that the result lines and the skip line carry.
        let name: String

        /// The request that the model gets, before
        /// ``GitScenarioTests/shortAnswerRequest``.
        let prompt: String

        /// The snippet call path of each verb that the snippets must call,
        /// without the `tools.` prefix.
        let verbPaths: Set<String>

        /// Whether the repository also holds a staged new file and an
        /// untracked file (``GitScenarioHistory/addUncommittedFiles(to:)``).
        let hasUncommittedFiles: Bool

        /// The facts that a correct answer names, from the sha of each
        /// commit, oldest first. The `RESULT` line prints the count; no test
        /// asserts it.
        let answerFacts: @Sendable ([String]) -> [String]

        /// The label, as the test report names the case.
        var testDescription: String { name }
    }

    /// The request at the end of each prompt.
    ///
    /// "One short sentence" keeps the answer as long as the printed score
    /// needs and no longer: each generated token costs approximately 0.2 s on
    /// the CI runner `mini`, and the whole suite must stay in 20 minutes. The
    /// first local run of this suite, with no such request, gave a reply of
    /// several lines for each scenario.
    private static let shortAnswerRequest = " Answer in one short sentence."

    /// The length of the short sha that git prints by default.
    private static let shortShaLength = 7

    /// The line of the blame scenario.
    private static let blameLine = GitScenarioHistory.greetingLine

    /// How many characters of the reply the `RESULT` line shows.
    private static let replyPreviewCharacters = 160

    /// The label of the check that the snippets called each verb.
    private static let calledTheVerbsCheckName = "calledTheVerbs"

    /// The label of the check that no `runCode` output holds a correction.
    private static let noCorrectionCheckName = "noCorrection"

    /// The text of a `correction` field with a value, in a JSON output.
    ///
    /// Computed, because `Regex` is not `Sendable` and a stored static value
    /// must be.
    private static var correctionField: Regex<Substring> { #/"correction"\s*:\s*"/# }

    /// The scenarios of the card, in the order of the card.
    static let scenarios = [
        GitScenario(
            name: "gitGoal",
            prompt: "Which files changed on the current git branch, and which functions changed in each "
                + "of them? Compare each changed file with its version at HEAD.",
            // `git.diff` only: the automatic mode of `diff` (no argument)
            // finds the changed files itself, thus a snippet that calls
            // `git.diff` alone also answers this prompt. A local run took that
            // route. The unit test `GitGoalSnippetTests` runs the goal snippet,
            // with `git.changes`, word for word.
            verbPaths: ["git.diff"],
            hasUncommittedFiles: false,
            answerFacts: { _ in [GitScenarioHistory.geometryPath, GitScenarioHistory.renamedFunctionName] }),
        GitScenario(
            name: "gitStatus",
            prompt: "Which files of the git repository have uncommitted changes? For each file, say if it "
                + "is staged, unstaged, or untracked.",
            verbPaths: ["git.status"],
            hasUncommittedFiles: true,
            answerFacts: { _ in
                [GitScenarioHistory.geometryPath, GitScenarioHistory.stagedNewPath, GitScenarioHistory.untrackedPath]
            }),
        GitScenario(
            name: "gitLog",
            prompt: "What are the subjects of the last three commits of the git repository, newest first?",
            verbPaths: ["git.log"],
            hasUncommittedFiles: false,
            answerFacts: { _ in GitScenarioHistory.subjects }),
        GitScenario(
            name: "gitShow",
            prompt: "What did the file \(GitScenarioHistory.greeterPath) hold two commits ago, at HEAD~2, "
                + "in the git repository? Quote its greeting.",
            verbPaths: ["git.show"],
            hasUncommittedFiles: false,
            answerFacts: { _ in [GitScenarioHistory.firstGreeting] }),
        GitScenario(
            name: "gitBlame",
            prompt: "In the git repository, which commit last changed line \(blameLine) of "
                + "\(GitScenarioHistory.greeterPath)? Give its sha and its author.",
            verbPaths: ["git.blame"],
            hasUncommittedFiles: false,
            answerFacts: { shas in shas.last.map { [String($0.prefix(shortShaLength))] } ?? [] }),
        GitScenario(
            name: "gitRenamedFunctionDiff",
            prompt: "In the git repository, compare \(GitScenarioHistory.geometryPath) at HEAD with the file "
                + "in the work folder, function by function. Which function has a new name, and what is "
                + "the new name?",
            verbPaths: ["git.diff"],
            hasUncommittedFiles: false,
            answerFacts: { _ in [GitScenarioHistory.functionName, GitScenarioHistory.renamedFunctionName] }),
    ]

    @Test("the model calls the git verbs of the scenario from a snippet, and no verb answers a correction",
          arguments: scenarios)
    func theModelReadsTheRepository(_ scenario: GitScenario) async throws {
        try await withLiveRouterFixture(name: scenario.name) { fixture in
            let (repository, shas) = try GitScenarioHistory.make()
            if scenario.hasUncommittedFiles {
                try GitScenarioHistory.addUncommittedFiles(to: repository)
            }
            let registry = try MultiTool.Builder().withGit(root: repository.workDirectory).buildRegistry()
            // No instructions, for the reason `runNativeIntegrationScenario`
            // gives: mounting the tools is the whole product surface.
            let seams = fixture.discoverySeams
            let session = fixture.profile.standard.makeSession(
                tools: try registry.makeSessionTools(selection: seams.selection, embedder: seams.embedder),
                discoveryPriming: scenarioDiscoveryPriming
            )

            let start = Date()
            let turn = try await streamTurn(of: session, prompt: scenario.prompt + Self.shortAnswerRequest)
            let elapsed = Date().timeIntervalSince(start)

            grade(scenario: scenario.name, checks: Self.checks(for: scenario, turn: turn))
            reportGatedResult(
                scenario: scenario.name,
                line: Self.resultLine(turn: turn, facts: scenario.answerFacts(shas), elapsed: elapsed))
        }
    }

    /// The conditions that one scenario is graded on: the verbs, then the
    /// corrections.
    ///
    /// - Parameters:
    ///   - scenario: The scenario that ran.
    ///   - turn: The streamed turn, with each session tool call it made.
    /// - Returns: Each condition, for `grade(scenario:checks:)`.
    private static func checks(for scenario: GitScenario, turn: StreamedTurn) -> [ScenarioCheck] {
        let typedPaths = NativeTranscript.typedToolPaths(in: turn.calls)
        let correctedOutputs = runCodeOutputs(of: turn).filter { $0.contains(correctionField) }
        return [
            ScenarioCheck(
                name: calledTheVerbsCheckName,
                held: scenario.verbPaths.isSubset(of: typedPaths),
                failureMessage:
                    "expected the \(MultiTool.runCodePath) snippets to call \(scenario.verbPaths.sorted()), "
                    + "but they called \(typedPaths.sorted()) and the calls were \(turn.calls.map(\.name))"
            ),
            ScenarioCheck(
                name: noCorrectionCheckName,
                held: correctedOutputs.isEmpty,
                failureMessage:
                    "expected no correction in a \(MultiTool.runCodePath) output, but got \(correctedOutputs)"
            ),
        ]
    }

    /// The output of each `runCode` call of the turn that completed.
    ///
    /// - Parameter turn: The streamed turn.
    /// - Returns: The outputs, in call order.
    private static func runCodeOutputs(of turn: StreamedTurn) -> [String] {
        turn.calls.filter { $0.name == MultiTool.runCodePath }.compactMap(\.output)
    }

    /// The `RESULT` line of one scenario.
    ///
    /// Built in named parts because one chained interpolation of this length
    /// times the type checker out.
    ///
    /// - Parameters:
    ///   - turn: The streamed turn.
    ///   - facts: The facts that a correct answer names.
    ///   - elapsed: How long the turn took, in seconds.
    /// - Returns: The reading to print after the scenario label.
    private static func resultLine(turn: StreamedTurn, facts: [String], elapsed: TimeInterval) -> String {
        let namedFacts = facts.filter { turn.answer.localizedCaseInsensitiveContains($0) }
        let route =
            "elapsed=\(elapsed)s tokens=\(turn.tokenUsage ?? "n/a") toolCalls=\(turn.toolCallCount) "
            + "calls=\(turn.calls.map(\.name)) "
        let snippets = "typed=\(NativeTranscript.typedToolPaths(in: turn.calls).sorted()) "
        let score = "answerFacts=\(namedFacts.count)/\(facts.count) named=\(namedFacts) "
        let failures = "priming=\(primingLabel(turn)) failedCalls=\(turn.failedCalls) "
        return route + snippets + score + failures + "reply=\"\(turn.answer.prefix(replyPreviewCharacters))\""
    }
}
