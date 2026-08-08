import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the did-you-mean repair hint: when a snippet calls a
/// `tools.*` path (or bare function) that does not exist, the rendered
/// error steers the model to the closest real catalog entries — turning
/// the wrong-guess dead end into a self-repair ramp — instead of leaving
/// only JavaScriptCore's bare `TypeError` text.
@Suite("UnknownToolHint")
struct UnknownToolHintTests {
    // MARK: - The two closing lines, read from the directive that renders them

    /// The closing line a repairable error carries when the snippet is worth
    /// fixing where it stands.
    ///
    /// Read off `RepairDirective` rather than spelled out again. A copy of
    /// the wording here would go on satisfying this file's negative
    /// expectations — `!output.contains(_:)` — after the shipped line was
    /// reworded, because output that no longer carries the old text passes
    /// them for the wrong reason.
    private static let repairClosing = RepairDirective.repairSnippet.closingLine

    /// The closing line a repairable error carries instead when the snippet
    /// named nothing the catalog defines.
    ///
    /// Read off `RepairDirective` for the same reason as `repairClosing`, and
    /// for one more: the tests below grade the two lines against each other,
    /// which holds only while both come from the enum that chooses between
    /// them.
    private static let discoveryClosing = RepairDirective.discoverFunctions.closingLine

    // MARK: - Unknown tools.* path: closest real path suggested

    /// A guess whose suggestion cannot be read out of the failed-path echo.
    ///
    /// Every hint opens with `tools.<the guess> does not exist`, so asserting
    /// that the output contains the *suggested* name passes on that echo alone
    /// whenever the guess spells the real name inside itself — which every
    /// containment-tier guess does, by definition. The tests below assert on
    /// the rendered `declare function` line instead: that text appears only in
    /// a real suggestion block.
    ///
    /// The guess itself is `getCitiesVisited` rather than `getCitiesOnTrip`
    /// for margin. `getCitiesOnTrip` scores exactly 0.2000 against `getTrip`
    /// — `similarityThreshold` itself, cleared only because the comparison is
    /// `>=` — and `getTrip` is a name this very file's `travelCatalog()`
    /// carries, so adding it to any catalog here would have made a
    /// zero-margin pair live and re-tiered a test silently. `getCitiesVisited`
    /// contains `getCities` (score 1.0) and scores at most 0.0556 against
    /// every other name in this file, 0.144 clear of the threshold.
    private static let citiesGuess = "getCitiesVisited"

    @Test("calling an unknown tools.* name suggests the closest real path")
    func unknownToolsCallSuggestsClosestRealPath() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.\(Self.citiesGuess)();")
        )

        #expect(output.contains("tools.\(Self.citiesGuess) does not exist"))
        #expect(output.contains("declare function getCities("))
        #expect(output.contains(Self.repairClosing))
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
        #expect(output.contains("declare function getTemperature("))
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
        #expect(output.contains("declare function getWeather("))
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

        // Measured 2026-08-07: asked for its full ranking, the searcher
        // answers `get itinerary` over this catalog with exactly
        // `["getTrip", "getWeather"]`, in that order, and adds nothing at a
        // higher limit. `relevanceSuggestionLimit` is 1, so a hint from this
        // tier shows only the first — and this assertion is what holds that
        // cut in place. `getWeather` has nothing to do with looking up a
        // trip; it ranks only because tier 2's ordering is relative, with no
        // absolute floor, and naming it hands a model that just guessed a
        // function name one more name to guess.
        #expect(!output.contains("tools.getWeather"))
    }

    // MARK: - A snippet that named nothing real is steered to discovery

    /// Replaces `unknownNameWithNoCloseMatchSteersToFindAPIs`, which drove
    /// this exact call against this exact catalog and asserted only that the
    /// word `findAPIs` appeared somewhere. Its two expectations are both kept
    /// below — `discoveryClosing` opens with `Call findAPIs`, so it subsumes
    /// the loose one — and the third is new.
    @Test("a snippet whose every tools.* path is unknown is steered to findAPIs, not back to runCode")
    func snippetNamingNothingRealIsSteeredToDiscovery() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.sendEmail({ to: 'a@b.c' });")
        )

        #expect(output.contains("tools.sendEmail does not exist"))
        #expect(output.contains(Self.discoveryClosing))
        #expect(!output.contains(Self.repairClosing))
    }

    @Test("a snippet that already reached a real tool keeps the repair-and-retry closing")
    func snippetThatReachedARealToolKeepsTheRepairClosing() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        // Same unknown path, same catalog, same `noMatch` tier as the test
        // above — the one difference is that this snippet also names
        // `tools.getCities`, which the catalog defines. A model holding a real
        // path has already discovered; it needs its snippet fixed, not a
        // search.
        let output = try await multiTool.call(
            arguments: RunCodeArguments(
                code: "const trip = await tools.getCities(); return tools.sendEmail(trip);"
            )
        )

        #expect(output.contains("tools.sendEmail does not exist"))
        #expect(output.contains(Self.repairClosing))
        #expect(!output.contains(Self.discoveryClosing))
    }

    @Test("a single-tool snippet written without any findAPIs call still runs and returns its value")
    func singleToolSnippetWithoutPriorDiscoveryStillSucceeds() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return (await tools.getCities()).cities;")
        )

        #expect(output == "[\"AAA\",\"BBB\",\"CCC\"]")
        #expect(!output.contains(Self.discoveryClosing))
        #expect(!output.contains(Self.repairClosing))
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
        #expect(output.contains(Self.repairClosing))
    }

    // MARK: - Imagined names reach the system log

    /// Ranks `failedPath` against `travelCatalog()` the way `MultiTool` does.
    ///
    /// `hint(message:snippet:surface:searcher:)` documents that its searcher
    /// must be indexing exactly `surface.entries`, which is the pairing
    /// `MultiTool.init` builds; these tier tests need the same pairing
    /// without a `runCode` round trip, so they can name a tier directly
    /// rather than inferring it from rendered text.
    ///
    /// - Parameter failedPath: the invented dotted path to resolve.
    /// - Returns: the resolution, or nil when the message names no unknown
    ///   path.
    /// - Throws: whatever `MultiTool.Builder.buildRegistry()` throws.
    private static func resolve(_ failedPath: String) async throws -> UnknownToolHint.Resolution? {
        let registry = try MultiTool.Builder().addTools(travelCatalog()).buildRegistry()
        return await UnknownToolHint.hint(
            message: "tools.\(failedPath) is not a function",
            snippet: "return tools.\(failedPath)();",
            surface: registry.surface,
            searcher: MetadataSearcher(items: registry.surface.entries, mode: .retrieval)
        )
    }

    @Test("a guess that resembles a real name is recorded against the resemblance tier")
    func resemblanceTierIsRecordedInTheLogMessage() async throws {
        let resolution = try #require(await Self.resolve("getWeatherOutlook"))

        #expect(resolution.imaginedPath == "getWeatherOutlook")
        #expect(resolution.tier == .nameResemblance)
        #expect(resolution.suggestedPaths == ["getWeather"])
        #expect(
            resolution.logMessage
                == "imaginedTool imagined=getWeatherOutlook tier=resemblance suggested=[getWeather]"
        )
    }

    @Test("a guess that resembles nothing is recorded against the relevance tier")
    func relevanceTierIsRecordedInTheLogMessage() async throws {
        let resolution = try #require(await Self.resolve("getItinerary"))

        #expect(resolution.tier == .catalogRelevance)
        #expect(resolution.suggestedPaths == ["getTrip"])
        #expect(
            resolution.logMessage
                == "imaginedTool imagined=getItinerary tier=relevance suggested=[getTrip]"
        )
    }

    @Test("a guess no tier can answer is recorded as such, with an empty suggestion list")
    func unansweredGuessIsRecordedWithNoTierAndNoSuggestions() async throws {
        // `buildRegistry()` rejects an empty tool set, so the catalog that
        // answers nothing is a one-tool catalog the guess has nothing to do
        // with: `getCities` neither contains nor is contained by
        // `sendEmail`, and the retrieval tier ranks only entries some signal
        // genuinely matched.
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()

        let resolution = try #require(
            await UnknownToolHint.hint(
                message: "tools.sendEmail is not a function",
                snippet: "return tools.sendEmail({ to: 'a@b.c' });",
                surface: registry.surface,
                searcher: MetadataSearcher(items: registry.surface.entries, mode: .retrieval)
            )
        )

        #expect(resolution.tier == .noMatch)
        #expect(resolution.suggestedPaths.isEmpty)
        #expect(
            resolution.logMessage == "imaginedTool imagined=sendEmail tier=none suggested=[]"
        )
    }

    /// The guess the emission test drives, spelled so that no other test in
    /// this process can produce a line carrying the same `imagined=` value —
    /// the log store is read per process, not per test.
    private static let emittedGuess = "getWeatherBulletin"

    @Test("an unknown tools.* path reaches the system log, exactly once")
    func unknownPathIsLoggedOnce() async throws {
        let registry = try MultiTool.Builder().addTools(Self.travelCatalog()).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let start = Date()

        _ = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.\(Self.emittedGuess)();")
        )

        let records = try await imaginedToolLogRecords(since: start, waitingFor: 1)
        #expect(
            records.filter { $0.imagined == Self.emittedGuess } == [
                ImaginedToolLogRecord(
                    imagined: Self.emittedGuess,
                    tier: "resemblance",
                    suggested: ["getWeather"]
                )
            ]
        )
    }

    /// The control guess the non-emission test emits *after* the call it is
    /// asserting produced nothing — see that test for why it is there.
    private static let controlGuess = "getWeatherDigest"

    @Test("a mis-called existing tool reaches the system log not at all")
    func misCalledExistingToolIsNotLogged() async throws {
        let registry = try MultiTool.Builder()
            .addTools(Self.travelCatalog())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let start = Date()

        // A real catalog path, called wrongly: the snippet takes the same
        // failure route the emitting test does, and the only difference is
        // that the path it names exists. The rendered text is checked so
        // this stays a mis-called *known* path rather than a snippet that
        // failed for some other reason.
        let misCall = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.getTemperature({});")
        )
        #expect(misCall.contains("getTemperature"))
        #expect(!misCall.contains("does not exist"))
        // Emitted second, and waited for below. Log delivery is ordered per
        // process, so a `getWeather` line would have had to arrive before
        // this one — which makes the absence below a real absence rather
        // than a read taken too early. It is also what keeps this test from
        // passing vacuously if the reader ever stopped working.
        _ = try await multiTool.call(
            arguments: RunCodeArguments(code: "return tools.\(Self.controlGuess)();")
        )

        let records = try await imaginedToolLogRecords(since: start, waitingFor: 1)
        #expect(records.contains { $0.imagined == Self.controlGuess })
        #expect(!records.contains { $0.imagined == "getTemperature" })
    }
}
