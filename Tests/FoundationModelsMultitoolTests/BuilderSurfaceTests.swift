import Foundation
import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// M2.5 coverage for `MultiTool.Builder` + `APISurface`: assembling queued
/// tools into a rendered, model-agnostic catalog — namespacing (flat vs.
/// grouped), collision detection, and the completeness contract
/// (`build()` throws rather than emit a lossy stub) — plan.md § "Adding
/// tools is the easy path" / Component 2/7.
@Suite("BuilderSurface")
struct BuilderSurfaceTests {
    @Test("a builder with a fixture set of standalone and grouped tools renders byte-identical to the golden file")
    func fixtureSetMatchesGoldenFile() throws {
        let surface = try MultiTool.Builder()
            .addTool(WeatherTool())
            .addTool(PlainTextTool())
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()

        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/BuilderSurface.ts.txt")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
            .trimmingCharacters(in: .newlines)

        #expect(surface.entries.map(\.path) == ["weather", "echo", "github.createIssue", "github.search"])
        #expect(surface.source.trimmingCharacters(in: .newlines) == golden)
    }

    @Test("two standalone tools with the same name make build() throw, naming the collision")
    func duplicateStandaloneNameThrows() throws {
        #expect {
            try MultiTool.Builder()
                .addTool(WeatherTool())
                .addTool(WeatherTool())
                .build()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == "weather"
        }
    }

    @Test("addGroup(named: \"github\", …) renders tools.github.<name> entries")
    func addGroupNamespacesEntries() throws {
        let surface = try MultiTool.Builder()
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()

        #expect(surface.entries.map(\.path) == ["github.createIssue", "github.search"])
        #expect(surface.entries.allSatisfy { $0.group == "github" })
        #expect(surface.source.contains("// tools.github.createIssue"))
        #expect(surface.source.contains("// tools.github.search"))
        // The grouped tool's own descriptor stays unqualified — the
        // namespace lives in `path`/the banner, not the declaration.
        #expect(surface.source.contains("declare function createIssue("))
    }

    @Test("two tools in different groups may share the same bare name — duplicates across groups are fine")
    func duplicateNameAcrossDifferentGroupsIsFine() throws {
        let surface = try MultiTool.Builder()
            .addGroup(named: "github", [GithubSearchTool()])
            .addGroup(named: "gitlab", [GitlabSearchTool()])
            .build()

        #expect(surface.entries.map(\.path) == ["github.search", "gitlab.search"])
    }

    @Test("two tools in the same group with the same name make build() throw, naming the collision")
    func duplicateNameWithinSameGroupThrows() throws {
        #expect {
            try MultiTool.Builder()
                .addGroup(named: "github", [GithubSearchTool(), GithubSearchTool()])
                .build()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == "search"
        }
    }

    @Test("a group name that isn't a legal TypeScript identifier makes build() throw")
    func illegalGroupNameThrows() throws {
        #expect {
            try MultiTool.Builder()
                .addGroup(named: "bad group!", [GithubSearchTool()])
                .build()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .illegalGroupName && builderError.name == "bad group!"
        }
    }

    @Test("a standalone tool name colliding with a group name makes build() throw, regardless of add order")
    func standaloneNameCollidingWithGroupNameThrows() throws {
        // Standalone added before the colliding group.
        #expect {
            try MultiTool.Builder()
                .addTool(GithubSearchTool()) // name: "search"
                .addGroup(named: "search", [GithubCreateIssueTool()])
                .build()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == "search"
        }

        // Same collision, reversed add order — the post-loop check is
        // order-independent.
        #expect {
            try MultiTool.Builder()
                .addGroup(named: "search", [GithubCreateIssueTool()])
                .addTool(GithubSearchTool()) // name: "search"
                .build()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == "search"
        }
    }

    @Test("a tool that can't be fully rendered makes build() throw, not emit a lossy stub")
    func unrenderableToolThrows() throws {
        #expect {
            try MultiTool.Builder()
                .addTool(IllegalNameTool())
                .build()
        } throws: { error in
            error is ToolAPIRendererError
        }
    }

    @Test("addTools(_:) queues every tool in the array, equivalent to calling addTool(_:) per element")
    func addToolsQueuesEveryElement() throws {
        let surface = try MultiTool.Builder()
            .addTools([WeatherTool(), PlainTextTool()])
            .build()

        #expect(surface.entries.map(\.path) == ["weather", "echo"])
    }
}
