// `EnumValueSynonymTests` — a common word for an allowed value of a string
// enum argument is read as that value, in any letter case, and the result
// carries a note that says so ("Postel's rule": be liberal in what you
// accept).
//
// noqueue24 django__django-14017 seq 6837:
// `tools.code_context.searchSymbol({ query, kind: "class" })` failed with
// `argument "kind" must be one of "function", "method", "type", "other"; got
// "class"`. The check is `ToolInvoker`'s, thus the mapping holds for every
// verb with a string enum.

import FoundationModels
import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The arguments of ``SymbolKindTool``: the `kind` enum of
/// `code_context.searchSymbol`.
@Generable
struct SymbolKindToolArguments {
    @Guide(description: "The name to search for.")
    var query: String

    @Guide(description: "The kind of symbol.", .anyOf(["function", "method", "type", "other"]))
    var kind: String?
}

/// What ``SymbolKindTool`` answers: the `kind` it received.
@Generable
struct SymbolKindToolOutput {
    var kind: String
}

/// A stub `searchSymbol` that answers the `kind` it received.
struct SymbolKindTool: Tool {
    let name = "searchSymbol"
    let description = "Answers the kind it received."

    func call(arguments: SymbolKindToolArguments) async throws -> SymbolKindToolOutput {
        SymbolKindToolOutput(kind: arguments.kind ?? "")
    }
}

@Suite struct EnumValueSynonymTests {

    /// The value of one call: the `kind` the verb received, and the notes.
    private struct Value: Decodable {
        let kind: String
        let notes: [String]?
    }

    /// Runs `tools.code_context.searchSymbol({ query: "X", kind })`.
    private static func call(kind: String) async throws -> String {
        let registry = try MultiTool.Builder()
            .addGroup(named: "code_context", [SymbolKindTool()])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(
                code: #"return await tools.code_context.searchSymbol({ query: "X", kind: "\#(kind)" });"#))
    }

    @Test(
        "a common word for a kind of type is read as type, with a note",
        arguments: ["class", "Class", "STRUCT", "enum", "interface", "protocol", "trait", "record"])
    func aTypeWordIsReadAsType(word: String) async throws {
        let output = try await Self.call(kind: word)

        #expect(!output.contains("must be one of"), "output was: \(output)")
        let value = try RunOutput.decoded(Value.self, from: output)
        #expect(value.kind == "type", "output was: \(output)")
        #expect(value.notes == [#"kind "\#(word)" was read as "type"."#], "output was: \(output)")
    }

    @Test("a common word for a function is read as function", arguments: ["func", "fn", "def", "Def"])
    func aFunctionWordIsReadAsFunction(word: String) async throws {
        let value = try RunOutput.decoded(Value.self, from: try await Self.call(kind: word))

        #expect(value.kind == "function")
        #expect(value.notes == [#"kind "\#(word)" was read as "function"."#])
    }

    @Test("an allowed value in another letter case is read as that value")
    func anotherLetterCaseIsReadAsTheValue() async throws {
        let value = try RunOutput.decoded(Value.self, from: try await Self.call(kind: "Method"))

        #expect(value.kind == "method")
        #expect(value.notes == [#"kind "Method" was read as "method"."#])
    }

    @Test("an allowed value carries no note")
    func anAllowedValueHasNoNote() async throws {
        let value = try RunOutput.decoded(Value.self, from: try await Self.call(kind: "type"))

        #expect(value.kind == "type")
        #expect(value.notes == nil)
    }

    @Test("a word that names no allowed value is still refused")
    func anUnknownWordIsRefused() async throws {
        let output = try await Self.call(kind: "variable")

        #expect(output.contains("must be one of"), "output was: \(output)")
    }
}
