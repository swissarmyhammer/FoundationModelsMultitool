import Foundation
import FoundationModels
import Testing
import os

@testable import FoundationModelsMultitool

/// M6 coverage for `Librarian`/`FindAPITool`/`FoundAPIs`: the assembled
/// librarian prefix, guided-splice-through via the `AgentSession` seam, the
/// capacity pre-filter + logging fallback, and fork-per-call prefix reuse —
/// plan.md § "Discovery: a prefix-cached librarian" + M6. Driven entirely
/// against the internal `AgentSession` seam (`Fixtures/LibrarianFixtures.swift`,
/// reusing M4b's `ScriptedAgentSession`) — zero GPU, no Router dependency,
/// the same pattern `MultiToolAgentTests` established.
@Suite("Librarian")
struct LibrarianTests {
    // MARK: - Assembled prefix golden file

    @Test("the assembled librarian prefix for a fixture surface matches the golden file")
    func assembledPrefixMatchesGoldenFile() throws {
        let surface = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addTool(WeatherTool())
            .build()

        let prefix = Librarian.assemblePrefix(surface: surface)

        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/LibrarianPrefix.txt")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
            .trimmingCharacters(in: .newlines)

        #expect(prefix.trimmingCharacters(in: .newlines) == golden)
        // The plan's own format: guidance, then a header, then every block.
        #expect(prefix.contains("# Available functions"))
        #expect(prefix.contains("declare function tripCities("))
        #expect(prefix.contains("declare function weather("))
    }

    // MARK: - Splice-through: a canned FoundAPIs result reaches the agent turn verbatim

    @Test("a fake guided session's canned FoundAPIs result splices into FindAPITool's output verbatim, via a fork() of the prefix-rooted session")
    func findAPIsSplicesCannedResultVerbatimThroughFork() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [cannedTripCitiesFoundAPIsJSON])
        let librarian = Librarian(surface: surface, capacityCharacterLimit: .max) { _ in root }
        let findAPITool = FindAPITool(librarian: librarian)

        let feedback = try await findAPITool.dispatch(task: "list the trip cities")

        #expect(root.forkCount == 1)
        #expect(feedback.contains("findAPIs(\"list the trip cities\") found:"))
        #expect(feedback.contains("tools.tripCities(): string[]"))
        #expect(feedback.contains("The cities on the user's current trip, in itinerary order."))
        #expect(feedback.contains("const cs = tools.tripCities();"))
    }

    @Test("an empty FoundAPIs result formats as a clear \"no matching functions\" message, not an empty string")
    func emptyFoundAPIsFormatsAsNoMatchMessage() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [cannedEmptyFoundAPIsJSON])
        let librarian = Librarian(surface: surface, capacityCharacterLimit: .max) { _ in root }
        let findAPITool = FindAPITool(librarian: librarian)

        let feedback = try await findAPITool.dispatch(task: "something no tool does")

        #expect(feedback == "findAPIs(\"something no tool does\") found no matching functions.")
    }

    // MARK: - fork()-per-call: the root session is cached, never queried directly

    @Test("each findAPIs call goes through its own fork() of the same cached root session, never the root's own respond(to:)")
    func eachFindAPIsCallGoesThroughItsOwnFork() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            cannedTripCitiesFoundAPIsJSON,
            cannedTripCitiesFoundAPIsJSON,
        ])
        let factoryCallCount = CallCounter()
        let librarian = Librarian(surface: surface, capacityCharacterLimit: .max) { _ in
            factoryCallCount.increment()
            return root
        }

        let first = try await librarian.findAPIs(task: "first task")
        let second = try await librarian.findAPIs(task: "second task")

        #expect(root.forkCount == 2)
        // The root session factory ran exactly once — the root is created
        // and cached on the first call, never rebuilt on the second.
        #expect(factoryCallCount.count == 1)
        #expect(first.functions.map(\.name) == ["tripCities"])
        #expect(second.functions.map(\.name) == ["tripCities"])
    }

    // MARK: - Capacity fallback (plan Resolved #6): pre-filter + logging

    @Test("an over-budget surface is lexically pre-filtered before seeding, the cut is reported, and the relevant block survives for a matching task")
    func overBudgetSurfacePreFiltersAndReportsTheCut() async throws {
        let surface = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addTool(WeatherTool())
            .build()
        let fullPrefix = Librarian.assemblePrefix(surface: surface)
        // A capacity comfortably under the full prefix's length, but large
        // enough that a single filtered block still fits — forces the
        // pre-filter path without making it unsatisfiable.
        let capacity = fullPrefix.count / 2

        let factory = RecordingSessionFactory(responses: [cannedWeatherFoundAPIsJSON])
        let cutEventBox = OSAllocatedUnfairLock<Librarian.PrefilterCutEvent?>(initialState: nil)
        let librarian = Librarian(
            surface: surface,
            capacityCharacterLimit: capacity,
            onPrefilterCut: { event in cutEventBox.withLock { $0 = event } },
            makeSession: factory.makeSession
        )

        // Deliberately avoids generic words ("the", "current") that appear
        // in *both* fixture tools' rendered text — "weather" is the one
        // significant word unique to `WeatherTool`'s block.
        let found = try await librarian.findAPIs(task: "weather forecast")

        let cut = try #require(cutEventBox.withLock { $0 })
        #expect(cut.totalBlocks == 2)
        #expect(cut.keptBlocks == 1)
        #expect(cut.fullPrefixCharacterCount == fullPrefix.count)
        #expect(cut.capacityCharacterLimit == capacity)

        // The filtered instructions actually seeded into the one-off session
        // kept the relevant "weather" block and cut the irrelevant one.
        let seededInstructions = try #require(factory.receivedInstructions.first)
        #expect(seededInstructions.contains("declare function weather("))
        #expect(!seededInstructions.contains("declare function tripCities("))

        #expect(found.functions.map(\.name) == ["weather"])
    }

    @Test("lexicallyFilter keeps every entry when the task has no significant words to match on")
    func lexicallyFilterKeepsEveryEntryForAnUnfilterableTask() throws {
        let surface = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addTool(WeatherTool())
            .build()

        let (filtered, keptCount) = Librarian.lexicallyFilter(surface: surface, task: "a an is")

        #expect(keptCount == 2)
        #expect(filtered.entries.count == 2)
    }

    @Test("lexicallyFilter matches a keyword found anywhere in a block's rendered text, not only its name")
    func lexicallyFilterMatchesKeywordInDocText() throws {
        let surface = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addTool(WeatherTool())
            .build()

        let (filtered, keptCount) = Librarian.lexicallyFilter(surface: surface, task: "itinerary")

        #expect(keptCount == 1)
        #expect(filtered.entries.map(\.descriptor.name) == ["tripCities"])
    }

    // MARK: - Grammar derivation (pure, no GPU)

    @Test("Librarian.grammarSchemaSource() derives a JSON Schema string naming FoundAPIs' fields")
    func grammarSchemaSourceDerivesFoundAPIsSchema() throws {
        let schema = try Librarian.grammarSchemaSource()

        #expect(schema.contains("functions"))
        #expect(schema.contains("signature"))
        #expect(schema.contains("example"))
    }
}
