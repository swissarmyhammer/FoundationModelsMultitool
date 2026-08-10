import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The two `tools.*` paths `MultiTool` binds itself, beyond the registry's
/// own entries.
///
/// A gated discovery run wrote `tools.searchTools(...)` in a snippet, got an
/// invented-path error, and spent the whole turn thrashing (task `bwk7knm`).
/// The guess was reasonable, so the surface accepts it: both siblings are real
/// bindings, reachable the same way every catalog tool is.
@Suite("Sibling tools.* paths")
struct SiblingToolPathTests {
    // MARK: - tools.runCode

    @Test("a snippet reaches a nested runCode and gets the inner snippet's value")
    func nestedRunCodeReturnsInnerValue() async throws {
        let multiTool = MultiTool(registry: try Self.registry())

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return await tools.runCode("return 1 + 1;");"#)
        )

        #expect(output == "2")
    }

    @Test("a nested runCode reaches the same catalog the outer snippet does")
    func nestedRunCodeSeesTheSameCatalog() async throws {
        let multiTool = MultiTool(registry: try Self.registry())

        let output = try await multiTool.call(
            arguments: RunCodeArguments(
                code: #"return await tools.runCode("const r = await tools.getCities({}); return r.cities.length;");"#
            )
        )

        #expect(output == "3")
    }

    @Test("recursion past the depth cap ends in a repairable error naming the cap, rather than running away")
    func nestedRunCodeStopsAtTheDepthCap() async throws {
        let multiTool = MultiTool(registry: try Self.registry())
        // One snippet deeper than the cap allows, written as nested string
        // literals so each level is a real `tools.runCode` call.
        let innermost = #"return await tools.runCode(1);"#
        let middle = "return await tools.runCode(\(Self.jsString(innermost)));"
        let outer = "return await tools.runCode(\(Self.jsString(middle)));"

        let output = try await multiTool.call(arguments: RunCodeArguments(code: outer))

        #expect(output.contains("nests at most \(MultiTool.maxRunCodeDepth) deep"))
        // The cap is a repair instruction, not a dead end.
        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
    }

    @Test("the depth cap does not report tools.runCode as a path that does not exist")
    func theCapNeverCallsItsOwnPathInvented() async throws {
        let multiTool = MultiTool(registry: try Self.registry())
        let innermost = #"return await tools.runCode(1);"#
        let middle = "return await tools.runCode(\(Self.jsString(innermost)));"
        let outer = "return await tools.runCode(\(Self.jsString(middle)));"

        let output = try await multiTool.call(arguments: RunCodeArguments(code: outer))

        #expect(!output.contains("tools.runCode \(UnknownToolHint.missingPathPhrase)"))
    }

    // MARK: - tools.searchTools

    @Test("tools.searchTools is bound when the session mounts a discovery tool")
    func searchToolsIsBoundWhenMounted() async throws {
        let registry = try Self.registry()
        let searchTools = try SearchToolsTool(registry: registry, librarian: nil)
        let multiTool = MultiTool(registry: registry, searchTools: searchTools)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return typeof tools.searchTools;")
        )

        #expect(output == #""function""#)
    }

    @Test("a snippet's tools.searchTools returns exactly what the mounted tool returns")
    func searchToolsInASnippetMatchesTheMountedTool() async throws {
        let registry = try Self.registry()
        let searchTools = try SearchToolsTool(registry: registry, librarian: nil)
        let multiTool = MultiTool(registry: registry, searchTools: searchTools)
        let query = "the cities on the trip"

        let direct = try await searchTools.call(arguments: SearchToolsArguments(task: query))
        let fromSnippet = try await multiTool.call(
            arguments: RunCodeArguments(code: "return await tools.searchTools(\(Self.jsString(query)));")
        )

        // The snippet's value is JSON, so the tool's own text is compared
        // against the decoded value rather than against a re-quoted copy.
        let decoded = try JSONDecoder().decode(String.self, from: Data(fromSnippet.utf8))
        #expect(decoded == direct)
    }

    @Test("tools.searchTools is absent when the registry mounts no discovery tool")
    func searchToolsIsAbsentInDirectMode() async throws {
        let multiTool = MultiTool(registry: try Self.registry())

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return typeof tools.searchTools;")
        )

        #expect(output == #""undefined""#)
    }

    // MARK: - Forgiving argument shapes

    @Test("both bindings take the object form the generated signatures teach")
    func bothBindingsAcceptTheObjectForm() async throws {
        let registry = try Self.registry()
        let searchTools = try SearchToolsTool(registry: registry, librarian: nil)
        let multiTool = MultiTool(registry: registry, searchTools: searchTools)

        let nested = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return await tools.runCode({ code: "return 7;" });"#)
        )
        let searched = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return await tools.searchTools({ task: "the cities" });"#)
        )

        #expect(nested == "7")
        #expect(searched.contains("tools.getCities"))
    }

    // MARK: - Fixtures

    /// A registry carrying one real tool, so a nested snippet has a catalog
    /// entry to reach for beyond the siblings themselves.
    private static func registry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// Renders `value` as a JavaScript string literal.
    ///
    /// The nesting tests build a snippet whose argument is itself a snippet,
    /// so the quoting has to survive two levels; `JSONEncoder` escapes it the
    /// same way JavaScript reads it.
    ///
    /// - Parameter value: the text to embed in generated JavaScript.
    /// - Returns: `value` as a quoted, escaped JS string literal.
    private static func jsString(_ value: String) -> String {
        String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
    }
}
