import Foundation
import FoundationModels
import FoundationModelsExtras

// MARK: - The value an inner `tools.*` call gives a snippet
//
// A tool whose output is a `@Generable` value crosses into a snippet as an
// object, through `ArgumentMarshaler.renderOutput`. A tool whose output is
// `String` crosses as text. That is the correct default for prose, but it is
// wrong for two kinds of text:
//
// - The pending envelope of a background tool. A snippet that read
//   `r.completionToken` from the text got `undefined` (SWE-bench run
//   `preds.code-context-1008`, instance `django__django-14016`: five
//   `getLines` calls failed with a missing `commandID`).
// - A report that a tool renders as JSON text because the engine of
//   FoundationModelsExtras runs only a `String` tool in the background —
//   `tools.shell.execute` is the one such tool. Its snippet must read
//   `r.exitCode` and `r.commandID`.
//
// So this file turns those two kinds of text into objects, and passes every
// other text through unchanged.

/// A tool whose `String` output has a structured value for a snippet.
///
/// The model reads the text as it is. Only an inner `tools.*` call of a
/// snippet reads the value that ``snippetValue(ofOutput:)`` gives.
protocol SnippetOutputShaping {
    /// The value that a snippet gets for one output of this tool.
    ///
    /// - Parameter output: The text that the call gave.
    /// - Returns: The value for the snippet.
    func snippetValue(ofOutput output: String) async -> InterpreterValue
}

/// The field names of the object that a pending envelope becomes.
enum SnippetPendingField {
    /// The flag that tells a snippet that the run continues. It is always
    /// `true`.
    static let pending = "pending"

    /// The completion token of the run.
    static let completionToken = "completionToken"

    /// What the model must do to get the result.
    static let next = "next"
}

extension PendingRunEnvelope {
    /// This envelope as the object a snippet gets:
    /// `{pending: true, completionToken, next}`.
    var snippetFields: [String: InterpreterValue] {
        [
            SnippetPendingField.pending: .bool(true),
            SnippetPendingField.completionToken: .string(completionToken),
            SnippetPendingField.next: .string(next),
        ]
    }
}

enum SnippetOutput {
    /// The value that a snippet gets for the output of `tool`.
    ///
    /// A ``SnippetOutputShaping`` tool decides for itself. For any other tool,
    /// a rendered pending envelope becomes its object, and every other output
    /// goes through `ArgumentMarshaler.renderOutput` unchanged.
    ///
    /// - Parameters:
    ///   - output: The output of the call.
    ///   - tool: The tool that gave it.
    /// - Returns: The value for the snippet.
    /// - Throws: What `ArgumentMarshaler.renderOutput` throws.
    static func value<Output: PromptRepresentable>(
        of output: Output, from tool: any Tool
    ) async throws -> InterpreterValue {
        guard let text = output as? String else {
            return try ArgumentMarshaler.renderOutput(output)
        }
        if let shaping = tool as? any SnippetOutputShaping {
            return await shaping.snippetValue(ofOutput: text)
        }
        if let envelope = PendingRunEnvelope.makeDecoded(fromRendered: text) {
            return .object(envelope.snippetFields)
        }
        return try ArgumentMarshaler.renderOutput(output)
    }
}
