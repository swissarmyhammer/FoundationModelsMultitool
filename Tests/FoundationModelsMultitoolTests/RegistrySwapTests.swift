import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the second half of rebuild-and-swap. eventplan.md
/// § "Consolidation of the siblings": "Then MultiTool swaps it in atomically
/// at the next turn boundary — the same boundary where the outbox folds in
/// events. Nothing changes below a snippet that runs. An in-flight run keeps
/// the registry that it started with."
///
/// Five facts carry this suite:
///
/// 1. `stage(_:)` then `turnWillBegin()` makes the next `runCode` see the new
///    verbs, and `help()`, `docs()` and `searchTools` see them at the same
///    time.
/// 2. `stage(_:)` with no `turnWillBegin()` leaves the current surface as it
///    is.
/// 3. A snippet in flight across a swap completes against the registry it
///    started with.
/// 4. Two stages then one tick give the newest registry.
/// 5. A fork made before a stage sees the swap after the tick: the fork and
///    its parent share one box.
@Suite("RegistrySwapTests")
struct RegistrySwapTests {

    // MARK: - Shared test constants

    /// The rendered path of `CitiesTool`.
    private static let citiesPath = "getCities"

    /// The rendered path of `TempTool`.
    private static let temperaturePath = "getTemperature"

    /// The group `IssueCountTool` renders under.
    private static let issueGroup = "github"

    /// The rendered path of `IssueCountTool`.
    private static let issueCountPath = "\(issueGroup).getIssueCount"

    /// The rendered path of `GatedTool`.
    private static let gatePath = "gated"

    /// The snippet that reads the surface of the sandbox as a list of paths.
    private static let helpSnippet = "return help();"

    /// The snippet that reads the docs of the temperature verb.
    private static let temperatureDocsSnippet = "return docs(\"\(temperaturePath)\");"

    /// The snippet that calls the temperature verb for one city.
    private static let temperatureSnippet = "return (await tools.\(temperaturePath)({ city: \"AAA\" })).tempC;"

    /// What ``temperatureSnippet`` renders: the fixture temperature of `AAA`.
    private static let temperatureOfAAA = "11"

    /// The snippet that blocks on the gate, then reads the cities verb of
    /// the registry the run started with.
    private static let gatedCitiesSnippet =
        "await tools.\(gatePath)(); return (await tools.\(citiesPath)()).cities.join(\"-\");"

    /// What ``gatedCitiesSnippet`` renders.
    private static let joinedCities = "\"AAA-BBB-CCC\""

    /// The discovery query that matches the cities verb.
    private static let citiesQuery = "the cities on the trip"

    /// The discovery query that matches the temperature verb.
    private static let temperatureQuery = "current temperature for a city"

    // MARK: - The ground of one test

    /// A registry over `CitiesTool` alone.
    private static func citiesRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// A registry over `TempTool` alone.
    private static func temperatureRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(TempTool()).buildRegistry()
    }

    /// A registry over `IssueCountTool` under ``issueGroup``.
    private static func issueRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addGroup(named: issueGroup, [IssueCountTool()]).buildRegistry()
    }

    /// The paths `help()` lists in a snippet run on `runCode`.
    ///
    /// - Parameter runCode: The tool to run the snippet on.
    /// - Returns: The paths, in render order.
    /// - Throws: What the run or the decode throws.
    private static func helpPaths(of runCode: MultiTool) async throws -> [String] {
        let rendered = try await runCode.call(arguments: RunCodeArguments(code: helpSnippet))
        return try JSONDecoder().decode([String].self, from: Data(rendered.utf8))
    }

    /// The mounted `runCode` and `searchTools` of `tools`, found by type.
    ///
    /// - Parameter tools: The array `makeSessionToolsAndStaging` vended.
    /// - Returns: The two tools.
    /// - Throws: When either is not in the array.
    private static func mounted(in tools: [any Tool]) throws -> (runCode: MultiTool, searchTools: SearchToolsTool) {
        let runCode = try #require(tools.compactMap { $0 as? MultiTool }.first)
        let searchTools = try #require(tools.compactMap { $0 as? SearchToolsTool }.first)
        return (runCode, searchTools)
    }

    // MARK: - Stage and tick

    @Test("stage then turnWillBegin makes runCode, help, docs and searchTools see the new verbs at the same time")
    func stageThenTickSwapsEverySurfaceAtOnce() async throws {
        let (tools, staging) = try Self.citiesRegistry().makeSessionToolsAndStaging(librarian: nil)
        let (runCode, searchTools) = try Self.mounted(in: tools)
        #expect(try await Self.helpPaths(of: runCode) == [Self.citiesPath])

        staging.stage(try Self.temperatureRegistry())
        await runCode.turnWillBegin()

        #expect(try await Self.helpPaths(of: runCode) == [Self.temperaturePath])
        let docs = try await runCode.call(arguments: RunCodeArguments(code: Self.temperatureDocsSnippet))
        #expect(docs.contains(Self.temperaturePath))
        let temperature = try await runCode.call(arguments: RunCodeArguments(code: Self.temperatureSnippet))
        #expect(temperature == Self.temperatureOfAAA)
        let discovery = try await searchTools.call(arguments: SearchToolsArguments(task: Self.temperatureQuery))
        #expect(discovery.contains("tools.\(Self.temperaturePath)"))
        #expect(!discovery.contains("tools.\(Self.citiesPath)"))
    }

    @Test("stage with no turnWillBegin leaves the current surface unchanged")
    func stageWithNoTickLeavesTheSurface() async throws {
        let (tools, staging) = try Self.citiesRegistry().makeSessionToolsAndStaging(librarian: nil)
        let (runCode, searchTools) = try Self.mounted(in: tools)

        staging.stage(try Self.temperatureRegistry())

        #expect(try await Self.helpPaths(of: runCode) == [Self.citiesPath])
        let discovery = try await searchTools.call(arguments: SearchToolsArguments(task: Self.citiesQuery))
        #expect(discovery.contains("tools.\(Self.citiesPath)"))
        #expect(!discovery.contains("tools.\(Self.temperaturePath)"))
    }

    @Test("two stages then one tick give the newest registry")
    func twoStagesThenOneTickGiveTheNewest() async throws {
        let runCode = MultiTool(registry: try Self.citiesRegistry())

        runCode.stage(try Self.temperatureRegistry())
        runCode.stage(try Self.issueRegistry())
        await runCode.turnWillBegin()

        #expect(try await Self.helpPaths(of: runCode) == [Self.issueCountPath])
    }

    // MARK: - A run in flight

    @Test("a snippet in flight across a swap completes against the registry it started with")
    func inFlightRunKeepsItsRegistry() async throws {
        let latch = ToolReleaseLatch()
        let gated = GatedTool(latch: latch)
        let first = try MultiTool.Builder().addTool(gated).addTool(CitiesTool()).buildRegistry()
        let runCode = MultiTool(registry: first)
        let run = Task {
            try await runCode.call(arguments: RunCodeArguments(code: Self.gatedCitiesSnippet))
        }
        try await TestPoll.waitUntil("the gated call started") { gated.hasStarted }

        // The swap lands while the snippet waits on the latch. The registry
        // it swaps to has no cities verb.
        runCode.stage(try Self.temperatureRegistry())
        await runCode.turnWillBegin()
        latch.release()

        #expect(try await run.value == Self.joinedCities)
        // The next run sees the swapped surface.
        #expect(try await Self.helpPaths(of: runCode) == [Self.temperaturePath])
    }

    // MARK: - Forks share the box

    @Test("a fork made before a stage sees the swap after the tick")
    func forkSeesTheSwapOfItsParent() async throws {
        let parent = MultiTool(registry: try Self.citiesRegistry())
        let fork = try #require(parent.forked() as? MultiTool)
        #expect(try await Self.helpPaths(of: fork) == [Self.citiesPath])

        parent.stage(try Self.temperatureRegistry())
        await parent.turnWillBegin()

        #expect(try await Self.helpPaths(of: fork) == [Self.temperaturePath])
        #expect(try await Self.helpPaths(of: parent) == [Self.temperaturePath])
    }

    @Test("a stage and a tick on the fork reach the parent")
    func parentSeesTheSwapOfItsFork() async throws {
        let parent = MultiTool(registry: try Self.citiesRegistry())
        let fork = try #require(parent.forked() as? MultiTool)

        fork.stage(try Self.issueRegistry())
        await fork.turnWillBegin()

        #expect(try await Self.helpPaths(of: parent) == [Self.issueCountPath])
    }
}
