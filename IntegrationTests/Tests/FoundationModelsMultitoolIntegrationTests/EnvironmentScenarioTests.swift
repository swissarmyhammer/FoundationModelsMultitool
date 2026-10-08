import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The gated scenario that proves that a real model reads the date through
/// the environment capability (task `^w2kryyf`).
///
/// **The mount.** `MultiTool.Builder().withEnvironment(context:)` and no
/// other capability, vended through `makeSessionTools(of:on:)` and mounted by
/// `runGatedTurnScenario(named:prompt:tools:reading:)` on the `RoutedSession`
/// that the resolved `.standard` slot vends. This is the wiring that a Router
/// host makes, the same as `GitScenarioTests`. The session gets no
/// instructions: the tool descriptions are the whole product surface.
///
/// **The injected clock.** The context gives a fixed clock and a fixed time
/// zone (the user's rule). Thus the expected date is the same on each run,
/// on each machine, and in each time zone of the machine. The date is far
/// from the date of each run, thus a model that does not call the verb
/// cannot know it. The `os` verb reads the real host.
///
/// **The scenario.** One short prompt, thus one model turn. Each model turn
/// costs approximately 100 s on the CI runner, and the CI integration job
/// must stay in 20 minutes. The unit tests of each verb call each verb
/// without a model. The scenario runs one time on each push. There is no
/// skip and no second round.
///
/// **The grade asserts code properties only** (the user's rule: a test does
/// not assert a fixed model score):
///
/// 1. A `runCode` snippet of the turn called `environment.now`. The record is
///    `StreamedTurn.calls`, read through `NativeTranscript.typedToolPaths(in:)`.
/// 2. No `runCode` output holds a `correction`.
/// 3. The answer holds the injected date: the injected weekday or the
///    injected `yyyy-MM-dd` date. The user's rule overrides the text of the
///    task here. The task said that only the `RESULT` line shows the weekday.
///
/// The `RESULT` line prints the token usage, the snippet verbs, and the
/// injected date.
@Suite(
    "Gated environment scenarios: a real model reads the date through tools.environment in runCode",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct EnvironmentScenarioTests {

    /// The label that the result line carries.
    private static let scenarioName = "environmentWeekdayAndOperatingSystem"

    /// The request that the model gets.
    ///
    /// "One short sentence" keeps the answer short: each generated token
    /// costs approximately 0.2 s on the CI runner, and the whole suite must
    /// stay in 20 minutes.
    private static let prompt =
        "What day of the week is it today, and which operating system is this? Answer in one short sentence."

    /// The snippet call path of each verb that the snippets must call,
    /// without the `tools.` prefix.
    private static let verbPaths: Set<String> = ["environment.now"]

    /// How many characters of the reply the `RESULT` line shows.
    private static let replyPreviewCharacters = 160

    /// The label of the check that the snippets called each verb.
    private static let calledTheVerbsCheckName = "calledTheVerbs"

    /// The label of the check that no `runCode` output holds a correction.
    private static let noCorrectionCheckName = "noCorrection"

    @Test("the model reads the injected date from a snippet, and no verb answers a correction")
    func theModelReadsTheInjectedDate() async throws {
        let registry = try MultiTool.Builder()
            .withEnvironment(context: InjectedDate.context())
            .buildRegistry()
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

    /// The conditions that the scenario is graded on: the verbs, the
    /// corrections, then the date in the answer.
    ///
    /// - Parameter turn: The streamed turn, with each session tool call it
    ///   made.
    /// - Returns: Each condition, for `grade(scenario:checks:)`.
    private static func checks(turn: StreamedTurn) -> [ScenarioCheck] {
        [
            calledTheVerbsCheck(named: calledTheVerbsCheckName, verbPaths: verbPaths, in: turn),
            ScenarioCheck.noCorrection(named: noCorrectionCheckName, in: turn),
            InjectedDate.answerCheck(of: turn),
        ]
    }

    /// The fields of the `RESULT` line that this scenario gives to
    /// `gatedResultLine(of:elapsed:readings:replyPreviewCharacters:)`: the
    /// token usage, the snippet verbs, the injected date, the priming, and
    /// the failed calls.
    ///
    /// - Parameter turn: The streamed turn.
    /// - Returns: The fields, in print order.
    private static func readings(of turn: StreamedTurn) -> [String] {
        [
            "tokens=\(turn.tokenUsage ?? "n/a")",
            typedPathsReading(of: turn),
            "injectedDate=\(InjectedDate.date) injectedWeekday=\(InjectedDate.weekday)",
            primingReading(of: turn),
            failedCallsReading(of: turn),
        ]
    }
}

/// The fixed clock and the fixed time zone of the environment scenario, and
/// the condition that the answer holds the date that they give.
enum InjectedDate {

    /// The seconds from 1970-01-01T00:00:00Z to ``instant``.
    static let secondsSince1970: TimeInterval = 1_907_506_800

    /// The instant that the clock gives at each call: 2030-06-12T15:00:00Z.
    static let instant = Date(timeIntervalSince1970: secondsSince1970)

    /// The time zone of the session. At ``instant`` the local time is
    /// 2030-06-12T17:00:00+02:00.
    static let timeZoneIdentifier = "Europe/Paris"

    /// The local date at ``instant``, as `tools.environment.now` gives it.
    static let date = "2030-06-12"

    /// The local day of the week at ``instant``, as `tools.environment.now`
    /// gives it.
    static let weekday = "Wednesday"

    /// The label of the check that the answer holds the injected date.
    static let answerCheckName = "answerHoldsTheInjectedDate"

    /// A context with the fixed clock and the fixed time zone. The other
    /// inputs read the real process.
    ///
    /// - Returns: The context.
    /// - Throws: An issue when the system does not know
    ///   ``timeZoneIdentifier``.
    static func context() throws -> EnvironmentContext {
        let zone = try #require(TimeZone(identifier: timeZoneIdentifier))
        return EnvironmentContext(now: { instant }, timeZone: zone)
    }

    /// The condition that the answer holds the injected date: the weekday or
    /// the `yyyy-MM-dd` date, in each letter case.
    ///
    /// - Parameter turn: The streamed turn.
    /// - Returns: The condition, for `grade(scenario:checks:)`.
    static func answerCheck(of turn: StreamedTurn) -> ScenarioCheck {
        ScenarioCheck(
            name: answerCheckName,
            held: [weekday, date].contains { turn.answer.localizedCaseInsensitiveContains($0) },
            failureMessage: "expected the answer to name \(weekday) or \(date), but the answer was \"\(turn.answer)\""
        )
    }
}

/// The offline checks of ``InjectedDate``. Each check makes a `StreamedTurn`
/// by hand, or calls the verb with no model. Thus each check always runs.
@Suite("Injected date: the clock of the environment scenario, and the check of the answer")
struct InjectedDateTests {

    /// A turn with one reply and no call.
    ///
    /// - Parameter answer: The reply of the turn.
    /// - Returns: The turn.
    private static func turn(answer: String) -> StreamedTurn {
        var turn = StreamedTurn()
        turn.answer = answer
        return turn
    }

    @Test("the verb gives the injected date and weekday over the injected context")
    func theVerbGivesTheInjectedDateAndWeekday() async throws {
        let result = try await Now(context: InjectedDate.context()).call(arguments: NowArguments(timeZone: nil))

        #expect(result.date == InjectedDate.date)
        #expect(result.weekday == InjectedDate.weekday)
        #expect(result.timeZone == InjectedDate.timeZoneIdentifier)
    }

    @Test("an answer that names the weekday in lower case holds the condition")
    func anAnswerThatNamesTheWeekdayHoldsTheCondition() {
        let check = InjectedDate.answerCheck(of: Self.turn(answer: "It is wednesday, on macOS."))

        #expect(check.name == InjectedDate.answerCheckName)
        #expect(check.held)
    }

    @Test("an answer that names only the yyyy-MM-dd date holds the condition")
    func anAnswerThatNamesTheDateHoldsTheCondition() {
        #expect(InjectedDate.answerCheck(of: Self.turn(answer: "Today is 2030-06-12 on macOS.")).held)
    }

    @Test("an answer that names a different day breaks the condition, and the message holds the answer")
    func anAnswerThatNamesADifferentDayBreaksTheCondition() {
        let answer = "It is Thursday, on macOS."
        let check = InjectedDate.answerCheck(of: Self.turn(answer: answer))

        #expect(!check.held)
        #expect(check.failureMessage.contains(answer))
    }
}
