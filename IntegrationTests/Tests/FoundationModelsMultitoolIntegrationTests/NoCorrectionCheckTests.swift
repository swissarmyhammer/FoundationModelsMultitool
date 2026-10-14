import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The offline checks of `ScenarioCheck.noCorrection(named:in:)`, the shared
/// condition that no `runCode` output of a gated answer holds a `correction`.
///
/// Each check makes a `StreamedAnswer` by hand. No check loads a model. Thus
/// each check always runs.
@Suite("No correction check: no runCode output of a gated answer holds a correction")
struct NoCorrectionCheckTests {

    /// The label that each check gives to the condition.
    private static let checkName = "noCorrection"

    /// The arguments of each `runCode` call. The check does not read them.
    private static let snippetArguments = #"{"code":"return await tools.environment.now({})"}"#

    /// A `runCode` output with a date and a `null` correction.
    private static let answeredOutput = #"{"date":"2030-06-12","correction":null}"#

    /// A `runCode` output with a correction that has a value.
    private static let correctedOutput = #"{"date":"","correction":"the time zone Not/AZone is not known"}"#

    /// An answer with one `runCode` call for each output.
    ///
    /// - Parameter outputs: The output of each call, or `nil` for a call
    ///   that did not complete.
    /// - Returns: The answer.
    private static func streamed(outputs: [String?]) -> StreamedAnswer {
        var answer = StreamedAnswer()
        answer.calls = outputs.map {
            NativeTranscript.StreamedCall(name: MultiTool.runCodePath, argumentsJSON: snippetArguments, output: $0)
        }
        return answer
    }

    @Test("an output with a null correction holds the condition")
    func anOutputWithANullCorrectionHoldsTheCondition() {
        let check = ScenarioCheck.noCorrection(named: Self.checkName, in: Self.streamed(outputs: [Self.answeredOutput]))

        #expect(check.name == Self.checkName)
        #expect(check.held)
    }

    @Test("an output with a correction that has a value breaks the condition, and the message names the output")
    func anOutputWithACorrectionBreaksTheCondition() {
        let check = ScenarioCheck.noCorrection(
            named: Self.checkName, in: Self.streamed(outputs: [Self.answeredOutput, Self.correctedOutput]))

        #expect(!check.held)
        #expect(check.failureMessage.contains(Self.correctedOutput))
    }

    @Test("a call with no output and a call that is not runCode do not break the condition")
    func aCallWithNoOutputOrAnotherNameDoesNotBreakTheCondition() {
        var answer = Self.streamed(outputs: [nil])
        answer.calls.append(
            NativeTranscript.StreamedCall(name: "listTools", argumentsJSON: "{}", output: Self.correctedOutput))

        #expect(ScenarioCheck.noCorrection(named: Self.checkName, in: answer).held)
    }
}
