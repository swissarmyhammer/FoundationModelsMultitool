import Foundation
import Testing

@testable import FoundationModelsMultitool

/// A minimal successful payload for the wire-shape tests.
private struct SamplePayload: Encodable {
    /// The one field the inline encoding must render at the top level.
    let value: String
}

/// A two-case outcome that mirrors the glob and grep outputs of the later
/// verb tasks: an inline success, or a corrective message.
private enum SampleOutcome: CorrectiveEncodable {
    /// The successful result.
    case content(SamplePayload)

    /// The corrective message the model reads and acts on.
    case corrective(String)

    /// The successful payload, or `nil` for a corrective outcome.
    var successResult: SamplePayload? {
        guard case .content(let payload) = self else { return nil }
        return payload
    }

    /// The corrective message, or `nil` for a successful outcome.
    var correctiveMessage: String? {
        guard case .corrective(let message) = self else { return nil }
        return message
    }
}

/// Behavioral tests for the shared corrective vocabulary: the
/// ``EnumParameter`` message rendering, the ``CorrectiveFailure``
/// resolution helpers, and the ``CorrectiveEncodable`` wire shape.
///
/// The rendered text is model-facing output. These cases pin it byte for
/// byte, thus the ported vocabulary renders the same messages the sibling
/// FileTool package renders.
@Suite struct CorrectiveVocabularyTests {
    // MARK: EnumParameter

    /// The accepted values render sorted ascending and comma-separated,
    /// thus a list built from dictionary keys reads in a stable order.
    @Test func nameListSortsTheValuesAndJoinsThemWithCommas() {
        #expect(EnumParameter.nameList(["text", "hashline", "raw"]) == "hashline, raw, text")
    }

    /// The unknown-value corrective names the parameter in backticks and
    /// lists the accepted values.
    @Test func unknownValueMessageNamesTheParameterAndTheAcceptedValues() {
        let message = EnumParameter.unknownValueMessage(
            validNames: ["text", "hashline", "raw"], parameterName: "format")
        #expect(message == "The `format` parameter must be one of: hashline, raw, text.")
    }

    // MARK: Corrective resolution

    /// A successful result runs the body with the resolved value.
    @Test func resolveRunsTheBodyOnSuccess() {
        let result: Result<Int, PathViolation> = .success(1)
        let outcome = result.resolve(
            corrective: { message in "corrective: \(message)" },
            then: { value in "resolved: \(value)" }
        )
        #expect(outcome == "resolved: 1")
    }

    /// A failed result short-circuits to the corrective outcome, built from
    /// the failure's own message.
    @Test func resolveShortCircuitsToTheCorrectiveOnFailure() {
        let result: Result<Int, PathViolation> = .failure(PathViolation("The path is outside the workspace."))
        let outcome = result.resolve(
            corrective: { message in "corrective: \(message)" },
            then: { value in "resolved: \(value)" }
        )
        #expect(outcome == "corrective: The path is outside the workspace.")
    }

    /// The asynchronous twin runs the awaiting body with the resolved value.
    @Test func resolveAsyncRunsTheBodyOnSuccess() async {
        let result: Result<Int, PathViolation> = .success(1)
        let outcome = await result.resolveAsync(
            corrective: { message in "corrective: \(message)" },
            then: { value in "resolved: \(value)" }
        )
        #expect(outcome == "resolved: 1")
    }

    /// The asynchronous twin short-circuits to the corrective outcome
    /// without running the body.
    @Test func resolveAsyncShortCircuitsToTheCorrectiveOnFailure() async {
        let result: Result<Int, PathViolation> = .failure(PathViolation("The path is outside the workspace."))
        let outcome = await result.resolveAsync(
            corrective: { message in "corrective: \(message)" },
            then: { value in "resolved: \(value)" }
        )
        #expect(outcome == "corrective: The path is outside the workspace.")
    }

    /// An ``PathCorrective/UnreadableFile`` failure resolves through the
    /// same protocol, thus the read and edit verbs hand its corrective back
    /// without a per-verb branch.
    @Test func anUnreadableFileResolvesToItsCorrectiveMessage() {
        let result: Result<Data, PathCorrective.UnreadableFile> = .failure(.init(path: "notes.txt"))
        let outcome = result.resolve(
            corrective: { message in message },
            then: { _ in "resolved" }
        )
        #expect(outcome == "The file could not be read: notes.txt")
    }

    // MARK: Wire shape

    /// Encodes an outcome as compact JSON with sorted keys.
    ///
    /// - Parameter outcome: the outcome to encode.
    /// - Returns: the encoded JSON text.
    /// - Throws: rethrows an encoding failure.
    private static func encoded(_ outcome: SampleOutcome) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(outcome), as: UTF8.self)
    }

    /// A successful outcome encodes its result's own fields inline at the
    /// top level.
    @Test func aSuccessfulOutcomeEncodesItsFieldsInline() throws {
        let json = try Self.encoded(.content(SamplePayload(value: "hello")))
        #expect(json == #"{"value":"hello"}"#)
    }

    /// A corrective outcome encodes a single `corrective` field carrying
    /// the message.
    @Test func aCorrectiveOutcomeEncodesASingleCorrectiveField() throws {
        let json = try Self.encoded(.corrective("The `format` parameter must be one of: hashline, raw, text."))
        #expect(json == #"{"corrective":"The `format` parameter must be one of: hashline, raw, text."}"#)
    }
}
