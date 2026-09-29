import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the second half of rebuild-and-swap. eventplan.md
/// § "Consolidation of the siblings": "Then MultiTool swaps it in atomically
/// at the next turn boundary — the same boundary where the outbox folds in
/// events. Nothing changes below a snippet that runs. An in-flight run keeps
/// the registry that it started with."
///
/// Router gives this boundary through `submissionWillBegin()`. The Router
/// calls it before each submission, and a continuation of one answer is a
/// submission too.
///
/// Six facts carry this suite:
///
/// 1. `stage(_:)` then `submissionWillBegin()` makes the next `runCode` see
///    the new verbs, and `help()`, `docs()` and `searchTools` see them at the
///    same time.
/// 2. `stage(_:)` with no `submissionWillBegin()` leaves the current surface
///    as it is.
/// 3. A snippet in flight across a swap completes against the registry it
///    started with.
/// 4. Two stages then one tick give the newest registry.
/// 5. A fork made before a stage sees the swap after the tick: the fork and
///    its parent share one box.
/// 6. A swap between two submissions of one answer turns a later call to a
///    removed verb into the repairable unknown-verb hint.
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

    /// The snippet that reads the docs of the temperature verb.
    private static let temperatureDocsSnippet = "return docs(\"\(temperaturePath)\");"

    /// The snippet that calls the temperature verb for one city.
    private static let temperatureSnippet = "return (await tools.\(temperaturePath)({ city: \"AAA\" })).tempC;"

    /// What ``temperatureSnippet`` renders: the fixture temperature of `AAA`.
    private static let temperatureOfAAA = "11"

    /// The snippet that calls the cities verb and joins the cities.
    private static let citiesSnippet = "return (await tools.\(citiesPath)()).cities.join(\"-\");"

    /// The snippet that blocks on the gate, then runs ``citiesSnippet`` on
    /// the registry the run started with.
    private static let gatedCitiesSnippet = "await tools.\(gatePath)(); \(citiesSnippet)"

    /// What ``citiesSnippet`` and ``gatedCitiesSnippet`` render.
    private static let joinedCities = "\"AAA-BBB-CCC\""

    /// The repair hint a call to the cities verb gets when the surface has
    /// no cities verb.
    private static let missingCitiesHint = "tools.\(citiesPath) \(UnknownToolHint.missingPathPhrase)"

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

    @Test("stage then submissionWillBegin makes runCode, help, docs and searchTools see the new verbs at the same time")
    func stageThenTickSwapsEverySurfaceAtOnce() async throws {
        let (tools, staging) = try Self.citiesRegistry().makeSessionToolsAndStaging(selection: nil)
        let (runCode, searchTools) = try Self.mounted(in: tools)
        #expect(try await helpPaths(of: runCode) == [Self.citiesPath])

        staging.stage(try Self.temperatureRegistry())
        await runCode.submissionWillBegin()

        #expect(try await helpPaths(of: runCode) == [Self.temperaturePath])
        let docs = try await runCode.call(arguments: RunCodeArguments(code: Self.temperatureDocsSnippet))
        #expect(docs.contains(Self.temperaturePath))
        let temperature = try await runCode.call(arguments: RunCodeArguments(code: Self.temperatureSnippet))
        #expect(temperature == Self.temperatureOfAAA)
        let discovery = try await searchTools.call(arguments: SearchToolsArguments(task: Self.temperatureQuery))
        #expect(discovery.contains("tools.\(Self.temperaturePath)"))
        #expect(!discovery.contains("tools.\(Self.citiesPath)"))
    }

    @Test("stage with no submissionWillBegin leaves the current surface unchanged")
    func stageWithNoTickLeavesTheSurface() async throws {
        let (tools, staging) = try Self.citiesRegistry().makeSessionToolsAndStaging(selection: nil)
        let (runCode, searchTools) = try Self.mounted(in: tools)

        staging.stage(try Self.temperatureRegistry())

        #expect(try await helpPaths(of: runCode) == [Self.citiesPath])
        let discovery = try await searchTools.call(arguments: SearchToolsArguments(task: Self.citiesQuery))
        #expect(discovery.contains("tools.\(Self.citiesPath)"))
        #expect(!discovery.contains("tools.\(Self.temperaturePath)"))
    }

    @Test("two stages then one tick give the newest registry")
    func twoStagesThenOneTickGiveTheNewest() async throws {
        let runCode = MultiTool(registry: try Self.citiesRegistry())

        runCode.stage(try Self.temperatureRegistry())
        runCode.stage(try Self.issueRegistry())
        await runCode.submissionWillBegin()

        #expect(try await helpPaths(of: runCode) == [Self.issueCountPath])
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
        await runCode.submissionWillBegin()
        latch.release()

        #expect(try await run.value == Self.joinedCities)
        // The next run sees the swapped surface.
        #expect(try await helpPaths(of: runCode) == [Self.temperaturePath])
    }

    // MARK: - A boundary inside one answer

    @Test("a swap between two submissions of one answer gives a later call to the removed verb the repair hint")
    func swapBetweenTwoSubmissionsOfOneAnswerGivesTheRepairHint() async throws {
        let runCode = MultiTool(registry: try Self.citiesRegistry())

        // The first submission of the answer calls the cities verb.
        let first = try await runCode.call(arguments: RunCodeArguments(code: Self.citiesSnippet))
        #expect(first == Self.joinedCities)

        // A registry with no cities verb is staged while the answer runs.
        // The Router calls the hook again before the continuation submission
        // of the same answer: a compaction yield, a rejected tool call, or a
        // repetition recovery.
        runCode.stage(try Self.temperatureRegistry())
        await runCode.submissionWillBegin()

        // The continuation calls the removed verb. The call does not throw:
        // the model gets the unknown-verb hint and can repair its snippet.
        let repaired = try await runCode.call(arguments: RunCodeArguments(code: Self.citiesSnippet))
        #expect(repaired.contains(Self.missingCitiesHint), "answer was: \(repaired)")
    }

    // MARK: - Forks share the box

    @Test("a fork made before a stage sees the swap after the tick")
    func forkSeesTheSwapOfItsParent() async throws {
        let parent = MultiTool(registry: try Self.citiesRegistry())
        let fork = try #require(parent.forked() as? MultiTool)
        #expect(try await helpPaths(of: fork) == [Self.citiesPath])

        parent.stage(try Self.temperatureRegistry())
        await parent.submissionWillBegin()

        #expect(try await helpPaths(of: fork) == [Self.temperaturePath])
        #expect(try await helpPaths(of: parent) == [Self.temperaturePath])
    }

    @Test("a stage and a tick on the fork reach the parent")
    func parentSeesTheSwapOfItsFork() async throws {
        let parent = MultiTool(registry: try Self.citiesRegistry())
        let fork = try #require(parent.forked() as? MultiTool)

        fork.stage(try Self.issueRegistry())
        await fork.submissionWillBegin()

        #expect(try await helpPaths(of: parent) == [Self.issueCountPath])
    }
}
