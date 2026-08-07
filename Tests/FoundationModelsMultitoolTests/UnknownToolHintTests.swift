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
            arguments: RunCodeArguments(code: "return tools.getCitiesOnTrip();")
        )

        #expect(output.contains("tools.getCitiesOnTrip does not exist"))
        #expect(output.contains("tools.getCities"))
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
            arguments: RunCodeArguments(code: "return tools.getTemperature.getCurrent({ city: 'ATX' });")
        )

        #expect(output.contains("tools.getTemperature.getCurrent does not exist"))
        #expect(output.contains("tools.getTemperature"))
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

    // MARK: - Wrong guesses against a realistic verbNoun catalog

    /// A realistic travel catalog for the ranking tests: two tools a
    /// trip-shaped guess could be reaching for, plus the trip-adjacent
    /// entries that genuinely compete with `getTrip` for one.
    ///
    /// Every name is verbNoun, the convention a real host catalog is
    /// consistent about. These tests previously ran against `weather` and
    /// `tripCities`, and graded `getTrip`/`getWeather` as invented names —
    /// but the human ruling of 2026-08-07 (task `tkrdwb8`) established that
    /// those were the model correctly inferring the catalog's dominant
    /// convention against two fixtures that broke it. With the fixtures
    /// following the convention, both guesses are real names, so the tests
    /// below are re-based on names that are genuinely absent.
    ///
    /// - Returns: the tools to build the ranking registry over.
    private static func travelCatalog() -> [any Tool] {
        [
            CatalogEntryTool(
                name: "getWeather",
                description: "Current weather for a city. Use when asked how warm/cold/rainy it is right now."
            ),
            CatalogEntryTool(
                name: "getTrip",
                description: "The cities on the user's current trip, in itinerary order."
            ),
            CatalogEntryTool(name: "bookHotel", description: "Books a hotel room for given dates."),
            CatalogEntryTool(name: "lookupFlight", description: "Looks up a flight's status by number."),
            CatalogEntryTool(name: "convertTimezone", description: "Converts a time between timezones."),
        ]
    }

    @Test("an invented name spelling out a real tool's name resolves to that tool")
    func inventedGetWeatherForecastResolvesToGetWeather() async throws {
        let registry = try MultiTool.Builder().addTools(Self.travelCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.getWeatherForecast({ city: 'ATX' });")
        )

        #expect(output.contains("tools.getWeatherForecast does not exist"))
        #expect(output.contains("tools.getWeather"))
    }

    /// The catalog-relevance tier's own coverage — the only test that reaches
    /// it, so the pair has to be one tier 1 genuinely cannot settle.
    ///
    /// `getItinerary` is contained by no catalog name and contains none, and
    /// its best character-trigram Jaccard against any entry is ≈0.07 (against
    /// `getTrip`, sharing only the `get` trigram) — far under
    /// `similarityThreshold`. So tier 1 finds nothing and ranking falls
    /// through to what the entries are *for*, where `getTrip`'s rendered
    /// block is the only one that says "itinerary".
    @Test("an invented name resembling nothing still resolves by catalog relevance")
    func inventedGetItineraryResolvesToGetTrip() async throws {
        let registry = try MultiTool.Builder().addTools(Self.travelCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getItinerary();"))

        #expect(output.contains("tools.getItinerary does not exist"))
        #expect(output.contains("tools.getTrip"))
    }

    @Test("a catalog-relevance hint names only its best match, not its runners-up")
    func catalogRelevanceHintNamesOnlyItsBestMatch() async throws {
        let registry = try MultiTool.Builder().addTools(Self.travelCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getItinerary();"))

        // Measured: ranking `get itinerary` over this catalog returns
        // exactly `["getTrip", "getWeather"]`, in that order. `getWeather`
        // has nothing to do with looking up a trip — it ranks only because
        // tier 2's ordering is relative, with no absolute floor — and naming
        // it hands a model that just guessed a function name one more name
        // to guess.
        #expect(!output.contains("tools.getWeather"))
    }

    // MARK: - Guard: a mis-called *existing* tool gets no did-you-mean noise

    @Test("a mis-called existing tool keeps its plain repairable error, with no does-not-exist hint")
    func misCalledExistingToolGetsNoHint() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getTemperature({});"))

        #expect(!output.contains("does not exist"))
        #expect(output.contains("Fix the snippet and call runCode again."))
    }
}
