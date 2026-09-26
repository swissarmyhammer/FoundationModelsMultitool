import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The time limit of the web research test, in minutes.
///
/// The turn is one turn of the shipped profile, and `SearchThenCallTests`
/// and `OperationToolLiveTests` give one such turn the same twelve minutes.
/// The web requests of the turn add little to that time, because
/// ``webRequestTimeoutSeconds`` and ``webResourceTimeoutSeconds`` stop each
/// slow request early. A run that reaches the limit is parked, not slow.
private let webResearchTimeLimitMinutes = 12

/// The label that the result lines and the skip line of the scenario carry.
private let webResearchScenarioName = "webResearch"

/// The request that the model gets, word for word from `web.md`.
private let webResearchPrompt =
    "Find the address of the home page of the Swift programming language on the web. Answer with the URL only."

/// The host that the answer must name: the home page of the Swift
/// programming language.
private let swiftHomePageHost = "swift.org"

/// The snippet call path of the search verb of the web capability.
///
/// `NativeTranscript.typedToolPaths(in:)` gives each path without the
/// `tools.` prefix, thus this is `tools.web.search` as a snippet writes it.
private let webSearchPath = "web.search"

/// The label of the check that a `runCode` snippet of the turn called
/// `tools.web.search`.
private let searchedTheWebCheckName = "searchedTheWeb"

/// How many seconds one web request can wait for more data before it fails.
///
/// A request that waits longer than this fails, and the search chain then
/// tries the next provider. Thus a provider that does not answer cannot use
/// the time limit of the test.
private let webRequestTimeoutSeconds: TimeInterval = 15

/// How many seconds one web request can take from start to end.
private let webResourceTimeoutSeconds: TimeInterval = 30

/// How many characters of the reply the `RESULT` line shows.
private let webResearchReplyPreviewCharacters = 120

/// The gated scenario that proves that a real model uses the web
/// capability: `web.md` § "Testing", Level 3.
///
/// **The mount.** `MultiTool.Builder().withWeb(configuration: .keyless)`,
/// vended through `MultiTool.Registry.makeSessionTools(librarian:)` and
/// mounted on the `RoutedSession` that the resolved `.standard` slot vends.
/// This is the wiring that `CLIRunner.runDemo` ships. `.keyless` reads no
/// environment, thus this scenario needs no API key, and it always runs, as
/// the environment rule of `IntegrationTests/Package.swift` asks. The web
/// requests go to the public keyless providers, with the short timeouts
/// above.
///
/// **The grade.** Two checks, from `web.md`:
///
/// 1. A `runCode` snippet of the turn called `tools.web.search`. The record
///    is `StreamedTurn.calls`, the record that `streamTurn` keeps of each
///    session tool call. `ScenarioCallLog` is not the record here, because
///    it holds the calls of fixture tools only, and `tools.web.search` is a
///    product verb. `OperationToolLiveTests` reads its route from the same
///    record for the same reason.
/// 2. The answer contains `swift.org`.
///
/// **Why the Router path, and not a bare session.** `FilesBareSessionTests`
/// mounts plain tools on a bare `LanguageModelSession`. That path has no
/// record of the snippet calls and does not queue behind
/// `liveProfileTurnstile`. This scenario needs both, thus it resolves a live
/// fixture through `withLiveRouterFixture`, which takes the turnstile.
///
/// Packaged like each gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipped
/// with a note when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated web research: a real model searches the web and names the Swift home page",
    .serialized,
    .timeLimit(.minutes(webResearchTimeLimitMinutes))
)
struct WebResearchScenarioTests {

    @Test("the model calls tools.web.search from a snippet and answers with swift.org")
    func searchesTheWebAndNamesTheSwiftHomePage() async throws {
        try await withLiveRouterFixture(name: webResearchScenarioName) { fixture in
            let registry = try MultiTool.Builder()
                .withWeb(
                    configuration: .keyless,
                    sessionConfiguration: ShortTimeoutSession.makeConfiguration(
                        requestTimeout: webRequestTimeoutSeconds, resourceTimeout: webResourceTimeoutSeconds))
                .buildRegistry()
            // No instructions, for the reason `runNativeIntegrationScenario`
            // gives: mounting the tools is the whole product surface.
            let session = fixture.profile.standard.makeSession(
                tools: try registry.makeSessionTools(librarian: fixture.profile.flash),
                discoveryPriming: scenarioDiscoveryPriming
            )

            let start = Date()
            let turn = try await streamTurn(of: session, prompt: webResearchPrompt)
            let elapsed = Date().timeIntervalSince(start)

            grade(scenario: webResearchScenarioName, checks: Self.webResearchChecks(turn: turn))
            reportGatedResult(
                scenario: webResearchScenarioName,
                line: Self.resultLine(turn: turn, elapsed: elapsed))
        }
    }

    /// The conditions that the web research run is graded on, in reporting
    /// order: the route, then the answer.
    ///
    /// - Parameter turn: the streamed turn, with each session tool call it
    ///   made.
    /// - Returns: each condition, for `grade(scenario:checks:)`.
    private static func webResearchChecks(turn: StreamedTurn) -> [ScenarioCheck] {
        let typedPaths = NativeTranscript.typedToolPaths(in: turn.calls)
        var checks = [
            ScenarioCheck(
                name: searchedTheWebCheckName,
                held: typedPaths.contains(webSearchPath),
                failureMessage:
                    "expected a \(MultiTool.runCodePath) snippet to call tools.\(webSearchPath), "
                    + "but the snippets called \(typedPaths.sorted()) and the calls were \(turn.calls.map(\.name))"
            )
        ]
        checks += answerChecks(turn.answer, containsOneOf: [swiftHomePageHost], mustNotContain: [])
        return checks
    }

    /// The `RESULT` line of the web research run.
    ///
    /// Built in named parts because one chained interpolation of this length
    /// times the type checker out.
    ///
    /// - Parameters:
    ///   - turn: the streamed turn.
    ///   - elapsed: how long the turn took, in seconds.
    /// - Returns: the reading to print after the scenario label.
    private static func resultLine(turn: StreamedTurn, elapsed: TimeInterval) -> String {
        let route = "elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) calls=\(turn.calls.map(\.name)) "
        let snippets = "typed=\(NativeTranscript.typedToolPaths(in: turn.calls).sorted()) "
        let failures = "priming=\(primingLabel(turn)) failedCalls=\(turn.failedCalls) "
        return route + snippets + failures
            + "reply=\"\(turn.answer.prefix(webResearchReplyPreviewCharacters))\""
    }
}
