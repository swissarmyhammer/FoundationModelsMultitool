import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// M7 coverage for `MultiTool`'s in-snippet `help()`/`docs()` globals —
/// in-language introspection backed by the very same `APISurface`/`Entry`
/// data that backs the librarian prefix and `findAPIs` (M2.5/M6), per
/// plan.md M7: "in-language introspection backed by the same `APISurface`
/// (one source of truth with the librarian prefix and findAPIs)."
///
/// Reuses `WeatherTool` (`ToolAPIRendererFixtures.swift`, plan.md's own
/// worked `weather` example) and `GithubCreateIssueTool`
/// (`BuilderSurfaceFixtures.swift`, plan.md's own worked grouped example)
/// rather than authoring bespoke fixtures — both are already the package's
/// canonical stand-ins for a standalone and a grouped tool.
@Suite("HelpDocs")
struct HelpDocsTests {
    /// A registry mixing a standalone tool (`weather`) and a grouped tool
    /// (`github.createIssue`), so `help()`'s grouped-layout entry (plan.md
    /// Resolved #5) has something real to report.
    private func makeRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder()
            .addTool(WeatherTool())
            .addGroup(named: "github", [GithubCreateIssueTool()])
            .buildRegistry()
    }

    // MARK: - help()

    @Test("runCode(\"return help()\") returns every tool's fully-qualified path, including group.name entries")
    func helpReturnsAllNamesIncludingGroupedEntries() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return help();"))

        let decoded = try JSONDecoder().decode([String].self, from: Data(output.utf8))
        #expect(decoded == ["weather", "github.createIssue"])
    }

    // MARK: - docs(name)

    @Test("runCode(\"return docs('weather')\") returns the exact rendered block from the surface")
    func docsReturnsExactRenderedBlockForStandaloneTool() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)
        let expectedEntry = try #require(registry.surface.entries.first { $0.path == "weather" })

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return docs('weather');"))

        let decoded = try JSONDecoder().decode(String.self, from: Data(output.utf8))
        #expect(decoded == expectedEntry.block)
    }

    @Test("docs('github.createIssue') returns the exact rendered block for a grouped tool")
    func docsReturnsExactRenderedBlockForGroupedTool() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)
        let expectedEntry = try #require(registry.surface.entries.first { $0.path == "github.createIssue" })

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return docs('github.createIssue');")
        )

        let decoded = try JSONDecoder().decode(String.self, from: Data(output.utf8))
        #expect(decoded == expectedEntry.block)
    }

    @Test("docs('nope') returns a helpful error naming close matches, not a crash")
    func docsUnknownNameReturnsErrorWithNearMatches() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)

        // "wether" is one deletion away from "weather" (edit distance 1),
        // and much farther from "github.createIssue" — so a distance-ranked
        // suggestion list should surface "weather" first.
        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return docs('wether');"))

        let decoded = try JSONDecoder().decode(String.self, from: Data(output.utf8))
        #expect(decoded.contains("weather"))
        #expect(decoded.lowercased().contains("unknown"))
    }

    @Test("docs() with no registered tools still returns a helpful, non-crashing message")
    func docsUnknownNameWithNoCandidatesStillDegradesGracefully() async throws {
        let registry = try MultiTool.Builder().buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return docs('anything');"))

        let decoded = try JSONDecoder().decode(String.self, from: Data(output.utf8))
        #expect(decoded.lowercased().contains("unknown"))
    }

    @Test("docs() called with no argument or a non-string argument returns a usage hint, not a crash")
    func docsWithMissingOrNonStringArgumentReturnsUsageHint() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)

        let missingArgumentOutput = try await multiTool.call(arguments: RunCodeArguments(code: "return docs();"))
        let numberArgumentOutput = try await multiTool.call(arguments: RunCodeArguments(code: "return docs(42);"))

        for output in [missingArgumentOutput, numberArgumentOutput] {
            let decoded = try JSONDecoder().decode(String.self, from: Data(output.utf8))
            #expect(decoded.contains("requires a string"))
        }
    }

    // MARK: - Sandbox: help()/docs() are the only new globals

    @Test("no globals beyond tools.*, help, and docs are newly reachable")
    func sandboxExposesOnlyHelpAndDocsAsNewGlobals() async throws {
        let registry = try makeRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                const checks = [
                    typeof help === 'function',
                    typeof docs === 'function',
                    typeof tools.weather === 'function',
                    typeof process === 'undefined',
                    typeof require === 'undefined',
                    typeof fetch === 'undefined',
                ];
                return checks.every(c => c === true);
                """)
        )

        #expect(output == "true")
    }
}
