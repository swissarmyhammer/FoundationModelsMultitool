import Foundation
import Testing

import FoundationModels

/// Coverage for the per-scenario failure-mode instrument — the derivation
/// `ScenarioRunner` reports a gated run's `MODES` line from.
///
/// Ungated on purpose. The modes exist so a gated run yields many counted
/// observations instead of one pass/fail bit, and a derivation nobody can
/// check off a live run is worth nothing: every rule below is exercised
/// here against evidence written out by hand, so the gated table means what
/// it says.
@Suite("Scenario failure modes")
struct ScenarioFailureModeTests {
    /// A run that did everything right, for the tests below to vary one
    /// field of at a time.
    ///
    /// - Returns: an observation with no failure mode present.
    private static func cleanRun() -> ScenarioObservation {
        ScenarioObservation(
            reply: "The warmest city on your trip is San Francisco.",
            toolCallCount: 2,
            invokedPaths: ["getTrip", "getWeather"],
            catalogPaths: ["getTrip", "getWeather"],
            findAPIsFirst: true,
            returnedValues: ["SFO", "San Francisco", "34"],
            validAnswer: true
        )
    }

    @Test("a clean run reports no failure mode except the route diagnostics")
    func aCleanRunReportsNoFailureMode() {
        let modes = ScenarioFailureModes(Self.cleanRun())

        #expect(!modes.overRefusal)
        #expect(!modes.answeredWithoutCalling)
        #expect(!modes.announceThenStop)
        #expect(modes.inventedPaths.isEmpty)
        #expect(!modes.thrash)
        #expect(!modes.groundedButWrongForm)
        #expect(modes.searchedFirst)
    }

    // MARK: - Over-refusal

    @Test("a reply that denies access with no tool call at all is an over-refusal")
    func denyingAccessWithoutCallingAnythingIsOverRefusal() {
        var observation = Self.cleanRun()
        // Recorded verbatim on task `tkrdwb8`, run C4.
        observation.reply = "I don't have access to your trip details or current weather data."
        observation.toolCallCount = 0
        observation.invokedPaths = []
        observation.validAnswer = false

        let modes = ScenarioFailureModes(observation)

        #expect(modes.overRefusal)
        // The same reply is not also counted as an answer the model simply
        // did not ground: a refusal is not a substantive answer.
        #expect(!modes.answeredWithoutCalling)
    }

    @Test("a reply that denies access after really calling a tool is not an over-refusal")
    func denyingAccessAfterCallingIsNotOverRefusal() {
        var observation = Self.cleanRun()
        observation.reply = "I don't have access to next week's forecast."
        observation.validAnswer = false

        #expect(!ScenarioFailureModes(observation).overRefusal)
    }

    // MARK: - Answered without calling

    @Test("a substantive answer with nothing invoked is answered-without-calling")
    func answeringWithNothingInvokedIsAnsweredWithoutCalling() {
        var observation = Self.cleanRun()
        observation.invokedPaths = []
        observation.returnedValues = []

        let modes = ScenarioFailureModes(observation)

        #expect(modes.answeredWithoutCalling)
        #expect(!modes.overRefusal)
        #expect(!modes.announceThenStop)
    }

    @Test("an empty reply with nothing invoked is not counted as an answer")
    func anEmptyReplyIsNotAnAnswer() {
        var observation = Self.cleanRun()
        observation.reply = "   \n"
        observation.invokedPaths = []
        observation.validAnswer = false

        #expect(!ScenarioFailureModes(observation).answeredWithoutCalling)
    }

    // MARK: - Announce then stop

    @Test("a reply that announces the next step and stops is announce-then-stop")
    func announcingAndStoppingIsAnnounceThenStop() {
        var observation = Self.cleanRun()
        observation.reply = "Let me first find the right function for your trip."
        observation.toolCallCount = 0
        observation.invokedPaths = []
        observation.validAnswer = false

        let modes = ScenarioFailureModes(observation)

        #expect(modes.announceThenStop)
        #expect(!modes.answeredWithoutCalling)
    }

    @Test("a reply that announces the next step and then takes it is not announce-then-stop")
    func announcingAndThenActingIsNotAnnounceThenStop() {
        var observation = Self.cleanRun()
        observation.reply = "Let me check — the warmest city is San Francisco."

        #expect(!ScenarioFailureModes(observation).announceThenStop)
    }

    // MARK: - Invented path

    @Test("a namespaced call against a flat catalog is an invented path")
    func namespacingAFlatCatalogEntryIsAnInventedPath() {
        var observation = Self.cleanRun()
        observation.invokedPaths = ["trips.getTrip", "getWeather"]

        #expect(ScenarioFailureModes(observation).inventedPaths == ["trips.getTrip"])
    }

    @Test("invented paths are reported in a stable order, however the set enumerates")
    func inventedPathsAreReportedSorted() {
        var observation = Self.cleanRun()
        observation.invokedPaths = ["zzzLast", "aaaFirst", "getTrip"]

        #expect(ScenarioFailureModes(observation).inventedPaths == ["aaaFirst", "zzzLast"])
    }

    // MARK: - Thrash

    @Test("a turn that stays within twice the calls it needs is not thrashing")
    func stayingWithinTwiceTheMinimumIsNotThrash() {
        var observation = Self.cleanRun()
        observation.toolCallCount = scenarioMinimumToolCalls * scenarioThrashFactor

        #expect(!ScenarioFailureModes(observation).thrash)
    }

    @Test("a turn that exceeds twice the calls it needs is thrashing")
    func exceedingTwiceTheMinimumIsThrash() {
        var observation = Self.cleanRun()
        observation.toolCallCount = scenarioMinimumToolCalls * scenarioThrashFactor + 1

        #expect(ScenarioFailureModes(observation).thrash)
    }

    // MARK: - Grounded but wrong form

    @Test("a wrong-form answer carrying a value the tools returned is grounded-but-wrong-form")
    func carryingReturnedDataInAWrongFormAnswerIsGroundedButWrongForm() {
        var observation = Self.cleanRun()
        // The recorded case: the compose scenario grades on a city name, and
        // the model answered with the temperature it had genuinely fetched.
        observation.reply = "It is 31°C right now."
        observation.returnedValues = ["31", "Austin"]
        observation.validAnswer = false

        #expect(ScenarioFailureModes(observation).groundedButWrongForm)
    }

    @Test("a wrong-form answer carrying nothing the tools returned is not grounded-but-wrong-form")
    func carryingNoReturnedDataIsNotGroundedButWrongForm() {
        var observation = Self.cleanRun()
        observation.reply = "It is 25°C right now."
        observation.returnedValues = ["31", "Austin"]
        observation.validAnswer = false

        #expect(!ScenarioFailureModes(observation).groundedButWrongForm)
    }

    @Test("an answer in the asserted form is never grounded-but-wrong-form")
    func anAnswerInTheAssertedFormIsNotGroundedButWrongForm() {
        var observation = Self.cleanRun()
        observation.reply = "San Francisco, at 34°C."

        #expect(!ScenarioFailureModes(observation).groundedButWrongForm)
    }

    @Test("a single character shared with a returned value does not count as grounding")
    func aSingleSharedCharacterIsNotGrounding() {
        var observation = Self.cleanRun()
        observation.reply = "There are 7 cities."
        observation.returnedValues = ["7"]
        observation.validAnswer = false

        #expect(!ScenarioFailureModes(observation).groundedButWrongForm)
    }

    // MARK: - The reported line

    @Test("the reported line carries every mode as a countable flag")
    func theReportedLineCarriesEveryModeAsAFlag() {
        var observation = Self.cleanRun()
        observation.invokedPaths = ["trips.getTrip"]
        observation.toolCallCount = 9

        let line = ScenarioFailureModes(observation).line(scenario: "composeChain")

        #expect(
            line == "MODES [composeChain] overRefusal=0 answeredWithoutCalling=0 "
                + "announceThenStop=0 inventedPath=1 searchedFirst=1 thrash=1 "
                + "groundedButWrongForm=0 invented=[trips.getTrip] toolCalls=9"
        )
    }

    // MARK: - What the tools actually returned

    @Test("a successful runCode output contributes every scalar the tools returned")
    func aSuccessfulRunCodeOutputContributesItsScalars() {
        let transcript = Transcript(entries: [
            .toolOutput(
                Transcript.ToolOutput(
                    id: "1",
                    toolName: "runCode",
                    segments: [
                        .text(
                            Transcript.TextSegment(
                                content: #"{"cities":["ATX","SFO"],"confirmed":true,"tempC":34}"#
                            )
                        )
                    ]
                )
            )
        ])

        // `true` is absent deliberately: a JSON boolean bridges to the same
        // numeric type as `1`, and "the reply contains 1" is not evidence
        // that any data came back.
        #expect(NativeTranscript.returnedValues(in: transcript) == ["ATX", "SFO", "34"])
    }

    @Test("a repairable-error runCode output contributes nothing")
    func aRepairableErrorOutputContributesNothing() {
        let transcript = Transcript(entries: [
            .toolOutput(
                Transcript.ToolOutput(
                    id: "1",
                    toolName: "runCode",
                    segments: [
                        .text(
                            Transcript.TextSegment(
                                content: "The snippet failed: TypeError: tools.getTrip is not a "
                                    + "function\n\nFix the snippet and call runCode again."
                            )
                        )
                    ]
                )
            )
        ])

        #expect(NativeTranscript.returnedValues(in: transcript).isEmpty)
    }

    @Test("a findAPIs output contributes nothing, however it is shaped")
    func aFindAPIsOutputContributesNothing() {
        let transcript = Transcript(entries: [
            .toolOutput(
                Transcript.ToolOutput(
                    id: "1",
                    toolName: "findAPIs",
                    segments: [.text(Transcript.TextSegment(content: #"["getTrip"]"#))]
                )
            )
        ])

        #expect(NativeTranscript.returnedValues(in: transcript).isEmpty)
    }
}
