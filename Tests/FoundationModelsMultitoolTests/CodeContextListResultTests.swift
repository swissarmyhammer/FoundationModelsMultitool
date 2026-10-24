// `CodeContextListResultTests` — the result of each list-shaped
// `code_context` verb also acts as its list ("Postel's rule": be liberal in
// what you accept).
//
// SWE-bench run bench24-1023b, django__django-14752 (seq 19079):
// `refs.map(...)` on a `grepCode` result threw "refs.map is not a function".

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The arguments of the stand-in location verbs.
@Generable
struct ListResultArguments {
    @Guide(description: "The symbol.")
    var symbol: String
}

/// One location of a stand-in location verb.
@Generable
struct ListResultLocation {
    @Guide(description: "The file.")
    var filePath: String
}

/// The result of the stand-in `getReferences`.
@Generable
struct ListResultReferences {
    @Guide(description: "The references.")
    var references: [ListResultLocation]
}

/// The result of the stand-in `getDefinition`.
@Generable
struct ListResultLocations {
    @Guide(description: "The locations.")
    var locations: [ListResultLocation]
}

/// A stand-in for `code_context.getReferences`.
struct ListResultReferencesTool: Tool {
    let name = "getReferences"
    let description = "Finds the references of a symbol."
    func call(arguments: ListResultArguments) async throws -> ListResultReferences {
        ListResultReferences(references: [ListResultLocation(filePath: "a.py"), ListResultLocation(filePath: "b.py")])
    }
}

/// A stand-in for `code_context.getDefinition`.
struct ListResultDefinitionTool: Tool {
    let name = "getDefinition"
    let description = "Finds the definition of a symbol."
    func call(arguments: ListResultArguments) async throws -> ListResultLocations {
        ListResultLocations(locations: [ListResultLocation(filePath: "c.py")])
    }
}

@Suite("CodeContextListResultTests")
struct CodeContextListResultTests {

    /// The snippet of the run, byte for byte.
    private static let refsSnippet = """
        const file = await tools.files.read({ path: "django/contrib/admin/views/autocomplete.py", offset: 88, limit: 40 });
        const refs = await tools.code_context.grepCode({ pattern: "AutocompleteJsonView", maxResults: 40 });
        return { file: file.lines, refs: refs.map(r => ({ file: r.filePath, line: r.line, text: r.text })) };
        """

    private struct Ref: Decodable, Equatable {
        let file: String
        let line: Int
        let text: String
    }

    private struct Answer: Decodable {
        let file: [String]
        let refs: [Ref]
    }

    /// Runs `code` with the files group over a root that holds the file of
    /// the run, beside the stand-in `code_context` verbs.
    private static func run(_ code: String) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("django/contrib/admin/views/autocomplete.py")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = (1...100).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: url)
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .addGroup(
                named: "code_context",
                [RepairMatchesTool(), ListResultReferencesTool(), ListResultDefinitionTool()] as [any Tool])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("the snippet of the run: a grepCode result maps as its matches")
    func grepCodeMapsAsItsMatches() async throws {
        let output = try await Self.run(Self.refsSnippet)
        let answer = try RunOutput.decoded(Answer.self, from: output)

        #expect(answer.refs == [Ref(file: "tests/x.py", line: 1, text: "AutocompleteJsonView")], "output was: \(output)")
        #expect(answer.file.count == 13, "output was: \(output)")
    }

    @Test("a getReferences result maps as its references")
    func getReferencesMapsAsItsReferences() async throws {
        let output = try await Self.run(
            #"const refs = await tools.code_context.getReferences({ symbol: "X" }); return refs.map((r) => r.file);"#)

        #expect(try RunOutput.decoded([String].self, from: output) == ["a.py", "b.py"], "output was: \(output)")
    }

    @Test("a getDefinition result reads as its locations")
    func getDefinitionReadsAsItsLocations() async throws {
        let output = try await Self.run(
            #"const d = await tools.code_context.getDefinition({ symbol: "X" }); return [d.length, d[0].filePath];"#)

        #expect(output.contains(#"[1,"c.py"]"#), "output was: \(output)")
    }
}
