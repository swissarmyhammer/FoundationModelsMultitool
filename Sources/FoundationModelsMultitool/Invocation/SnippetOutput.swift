import Foundation
import FoundationModels

// MARK: - The value an inner `tools.*` call gives a snippet
//
// A tool whose output is a `@Generable` value crosses into a snippet as an
// object, through `ArgumentMarshaler.renderOutput`, which also parses a text
// that is one whole JSON object or array. What this file adds is the step for
// a tool that knows more about its own text than a parse does:
// `tools.shell.execute` reads its report again from its store when the cap
// cut the text.
//
// An inner call never gives a snippet a pending object: each inner call runs
// to completion, and only the outer `runCode` call goes to the background
// (see `RunToCompletionInnerTool`, task `^6nnykct`).

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

/// The value that an inner `tools.*` call gives a snippet.
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
