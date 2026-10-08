import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The offline checks of `ScenarioCheck.noCorrection(named:in:)`, the shared
/// condition that no `runCode` output of a gated turn holds a `correction`.
///
/// Each check makes a `StreamedTurn` by hand. No check loads a model. Thus
/// each check always runs.
@Suite("No correction check: no runCode output of a gated turn holds a correction")
struct NoCorrectionCheckTests {

    /// The label that each check gives to the condition.
    private static let checkName = "noCorrection"

    /// The arguments of each `runCode` call. The check does not read them.
    private static let snippetArguments = #"{"code":"return await tools.environment.now({})"}"#

    /// A `runCode` output with a date and a `null` correction.
    private static let answeredOutput = #"{"date":"2030-06-12","correction":null}"#

    /// A `runCode` output with a correction that has a value.
    private static let correctedOutput = #"{"date":"","correction":"the time zone Not/AZone is not known"}"#

    /// A turn with one `runCode` call for each output.
    ///
    /// - Parameter outputs: The output of each call, or `nil` for a call
    ///   that did not complete.
    /// - Returns: The turn.
    private static func turn(outputs: [String?]) -> StreamedTurn {
        var turn = StreamedTurn()
        turn.calls = outputs.map {
            NativeTranscript.StreamedCall(name: MultiTool.runCodePath, argumentsJSON: snippetArguments, output: $0)
        }
        return turn
    }

    @Test("an output with a null correction holds the condition")
    func anOutputWithANullCorrectionHoldsTheCondition() {
        let check = ScenarioCheck.noCorrection(named: Self.checkName, in: Self.turn(outputs: [Self.answeredOutput]))

        #expect(check.name == Self.checkName)
        #expect(check.held)
    }

    @Test("an output with a correction that has a value breaks the condition, and the message names the output")
    func anOutputWithACorrectionBreaksTheCondition() {
        let check = ScenarioCheck.noCorrection(
            named: Self.checkName, in: Self.turn(outputs: [Self.answeredOutput, Self.correctedOutput]))

        #expect(!check.held)
        #expect(check.failureMessage.contains(Self.correctedOutput))
    }

    @Test("a call with no output and a call that is not runCode do not break the condition")
    func aCallWithNoOutputOrAnotherNameDoesNotBreakTheCondition() {
        var turn = Self.turn(outputs: [nil])
        turn.calls.append(
            NativeTranscript.StreamedCall(name: "listTools", argumentsJSON: "{}", output: Self.correctedOutput))

        #expect(ScenarioCheck.noCorrection(named: Self.checkName, in: turn).held)
    }
}
