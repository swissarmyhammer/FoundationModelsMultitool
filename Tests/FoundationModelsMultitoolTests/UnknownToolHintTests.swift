import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the did-you-mean repair hint: when a snippet calls a
/// `tools.*` path (or bare function) that does not exist, the rendered
/// error steers the model to the closest real catalog entries — turning
/// the wrong-guess dead end into a self-repair ramp — instead of leaving
/// only JavaScriptCore's bare `TypeError` text.
@Suite("UnknownToolHint")
struct UnknownToolHintTests {
    // MARK: - Unknown tools.* path: closest real path suggested

    @Test("calling an unknown tools.* name suggests the closest real path")
    func unknownToolsCallSuggestsClosestRealPath() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.getCities();")
        )

        #expect(output.contains("tools.getCities does not exist"))
        #expect(output.contains("tools.cities"))
        #expect(output.contains("Fix the snippet and call runCode again."))
    }

    // MARK: - Invented sub-path on a real tool

    @Test("calling an invented sub-path on a real tool suggests the real tool itself")
    func inventedSubPathSuggestsTheRealTool() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.temp.getCurrent({ city: 'ATX' });")
        )

        #expect(output.contains("tools.temp.getCurrent does not exist"))
        #expect(output.contains("tools.temp"))
    }

    // MARK: - No close match: steer back to findAPIs

    @Test("an unknown name with no close catalog match steers back to findAPIs")
    func unknownNameWithNoCloseMatchSteersToFindAPIs() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.sendEmail({ to: 'a@b.c' });")
        )

        #expect(output.contains("tools.sendEmail does not exist"))
        #expect(output.contains("findAPIs"))
    }

    // MARK: - Recorded gated failures: the names real runs actually invented

    /// The catalog recorded from the gated `discoveryUnderDistractors` runs
    /// that invented `tools.getTrip` and `tools.getWeather`: the two relevant
    /// tools, plus the trip-adjacent distractors that genuinely compete with
    /// `tripCities` for a trip-shaped guess.
    ///
    /// - Returns: the tools to build the reproduction registry over.
    private static func recordedDiscoveryCatalog() -> [any Tool] {
        [
            CatalogEntryTool(
                name: "weather",
                description: "Current weather for a city. Use when asked how warm/cold/rainy it is right now."
            ),
            CatalogEntryTool(
                name: "tripCities",
                description: "The cities on the user's current trip, in itinerary order."
            ),
            CatalogEntryTool(name: "bookHotel", description: "Books a hotel room for given dates."),
            CatalogEntryTool(name: "lookupFlight", description: "Looks up a flight's status by number."),
            CatalogEntryTool(name: "convertTimezone", description: "Converts a time between timezones."),
        ]
    }

    @Test("the invented tools.getWeather resolves to the real weather tool")
    func inventedGetWeatherResolvesToWeather() async throws {
        let registry = try MultiTool.Builder().addTools(Self.recordedDiscoveryCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.getWeather({ city: 'ATX' });")
        )

        #expect(output.contains("tools.getWeather does not exist"))
        #expect(output.contains("tools.weather"))
    }

    @Test("the invented tools.getTrip resolves to the real tripCities tool")
    func inventedGetTripResolvesToTripCities() async throws {
        let registry = try MultiTool.Builder().addTools(Self.recordedDiscoveryCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getTrip();"))

        #expect(output.contains("tools.getTrip does not exist"))
        #expect(output.contains("tools.tripCities"))
    }

    @Test("a catalog-relevance hint names only its best match, not its runners-up")
    func catalogRelevanceHintNamesOnlyItsBestMatch() async throws {
        let registry = try MultiTool.Builder().addTools(Self.recordedDiscoveryCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getTrip();"))

        // Measured: ranking `getTrip` over this catalog puts `tripCities`
        // first, then `convertTimezone` and `bookHotel` — runners-up that
        // have nothing to do with looking up a trip, and that a model which
        // just guessed a function name would only guess at again.
        #expect(!output.contains("tools.convertTimezone"))
        #expect(!output.contains("tools.bookHotel"))
    }

    // MARK: - Guard: a mis-called *existing* tool gets no did-you-mean noise

    @Test("a mis-called existing tool keeps its plain repairable error, with no does-not-exist hint")
    func misCalledExistingToolGetsNoHint() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.temp({});"))

        #expect(!output.contains("does not exist"))
        #expect(output.contains("Fix the snippet and call runCode again."))
    }
}
