import Foundation
import FoundationModels
import FoundationModelsExtras

// MARK: - The value an inner `tools.*` call gives a snippet
//
// A tool whose output is a `@Generable` value crosses into a snippet as an
// object, through `ArgumentMarshaler.renderOutput`. Before task ^38j4bbn, the
// pending envelope of `tools.shell.execute` crossed as text, and a snippet that
// read `r.completionToken` got `undefined` (SWE-bench run
// `preds.code-context-1008`, instance `django__django-14016`: five `getLines`
// calls failed with a missing `commandID`).
//
// `ArgumentMarshaler.renderOutput` parses a text that is one whole JSON object
// or array, and a rendered pending envelope is one. So a pending envelope
// already crosses as `{pending: true, completionToken, next}`. What this file
// adds is the step for a tool that knows more about its own text than a
// parse does: `tools.shell.execute` adds `commandID` to a pending result, and
// reads its report again from its store when the cap cut the text.

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
    /// A ``SnippetOutputShaping`` tool decides for itself. Every other output
    /// goes through `ArgumentMarshaler.renderOutput`.
    ///
    /// - Parameters:
    ///   - output: The output of the call.
    ///   - tool: The tool that gave it.
    /// - Returns: The value for the snippet.
    /// - Throws: What `ArgumentMarshaler.renderOutput` throws.
    static func value<Output: PromptRepresentable>(
        of output: Output, from tool: any Tool
    ) async throws -> InterpreterValue {
        if let text = output as? String, let shaping = tool as? any SnippetOutputShaping {
            return await shaping.snippetValue(ofOutput: text)
        }
        return try ArgumentMarshaler.renderOutput(output)
    }
}
