// `SymbolResultShapeTests` — a `code_context.listSymbol` / `getSymbol` result
// also acts as its `symbols` array ("Postel's rule").
//
// FoundationModelsCodeContext 502d26d changed `listSymbol` to answer
// `{ file, symbols: [...] }`, the shape of `getSymbol`. In SWE-bench run
// bench24-1023b (child session 01M5N8ZX1YBEW4V5T9456TG7H0) the model wrote
// both `syms.symbols.filter(...)` (seq 4598) and `syms.filter(...)` (seq
// 4606, the old bare-array form). Both must work.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// One symbol of the stand-in result.
@Generable
struct StandInSymbol {
    @Guide(description: "The name of the symbol.")
    var name: String
}

/// The stand-in result: the file, and its symbols.
@Generable
struct StandInSymbolsResult {
    @Guide(description: "The file.")
    var file: String
    @Guide(description: "The symbols.")
    var symbols: [StandInSymbol]
}

/// The arguments of the stand-in symbol verbs.
@Generable
struct StandInSymbolArguments {
    @Guide(description: "The file.")
    var file: String
}

/// A stand-in `code_context` verb that answers one `save` symbol.
struct StandInSymbolTool: Tool {
    let name: String
    let description = "Lists the symbols of one file."
    func call(arguments: StandInSymbolArguments) async throws -> StandInSymbolsResult {
        StandInSymbolsResult(file: arguments.file, symbols: [StandInSymbol(name: "save"), StandInSymbol(name: "load")])
    }
}

@Suite("SymbolResultShapeTests")
struct SymbolResultShapeTests {

    @Test("both syms.symbols.filter and syms.filter work on a symbol result", arguments: ["listSymbol", "getSymbol"])
    func bothFormsWork(verb: String) async throws {
        let registry = try MultiTool.Builder()
            .addGroup(
                named: "code_context",
                [StandInSymbolTool(name: "listSymbol"), StandInSymbolTool(name: "getSymbol")]
            )
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(
                code: """
                    const syms = await tools.code_context.\(verb)({ file: "django/db/models/base.py" });
                    return `${syms.symbols.filter(s => s.name === "save").length} ${syms.filter(s => s.name === "save").length} ${syms.file}`;
                    """))

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(try RunOutput.decoded(String.self, from: output) == "1 1 django/db/models/base.py", "output was: \(output)")
    }
}
