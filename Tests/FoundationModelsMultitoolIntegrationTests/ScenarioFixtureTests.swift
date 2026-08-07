import Testing

@testable import FoundationModelsMultitool

/// Ungated coverage for the premises the gated scenarios grade on
/// (`Fixtures/ScenarioTools.swift`).
///
/// Every assertion in `SearchThenCallTests` rests on something being true of
/// those fixtures — that exactly one trip city is warmest, that the trip tool
/// forces a snippet to navigate to `.cities`, that `getWeather` refuses an
/// argument it cannot resolve to one city, that no single reply can answer
/// both scenario questions. All four scenarios run only under
/// `MULTITOOL_INTEGRATION`, so until this suite existed a fixture edit could
/// break any of those premises and leave an ordinary `swift test` green while
/// the gated assertions quietly stopped meaning what they say.
///
/// These tests carry no gate on purpose. They need no model, no download and
/// no GPU: they render the surface and run snippets through the same
/// `MultiTool` a host mounts, and read the fixtures directly.
@Suite("Gated-scenario fixture premises")
struct ScenarioFixtureTests {
    // MARK: - The trip tool's object shape

    @Test("the trip tool renders as a multi-field object rather than a bare list of cities")
    func tripToolRendersAsAMultiFieldObject() throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool()).buildRegistry()

        let source = registry.surface.source

        // The rendered return type in full, rather than a sample of two of
        // its fields: the reshape buys nothing unless the declaration a model
        // reads names every sibling, so dropping one, renaming one or
        // reordering them all fail here.
        //
        // The shape this replaced is `Promise<{ cities: string[] }>` — an
        // object already, so `.cities` navigation is not what changed; the
        // four siblings are, and a single-field object is one a snippet can
        // consume without reading the declaration at all. A bare
        // `Promise<string[]>` was never one of the candidates: a tool's
        // `Output` is a `@Generable` struct, which `ToolAPIRenderer` always
        // renders as an object, so expecting a bare list to be absent would
        // expect nothing.
        #expect(
            source.contains(
                """
                Promise<{ confirmationCode: string; traveler: string; \
                startDate: string; endDate: string; cities: string[] }>
                """
            )
        )
    }

    @Test("a snippet reaches the itinerary through the trip result's cities field")
    func tripSnippetNavigatesToCities() async throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return (await tools.getTrip()).cities.join("-");"#)
        )

        #expect(output == "\"\(integrationCityWeather.map(\.code).joined(separator: "-"))\"")
    }

    @Test("a snippet that treats the whole trip result as the city list gets a repairable error")
    func tripSnippetThatSkipsCitiesFails() async throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return (await tools.getTrip()).join("-");"#)
        )

        #expect(output.contains("Fix the snippet and call runCode again."))
    }

    // MARK: - `getWeather` resolves exactly one city, or refuses

    @Test("every fixture city resolves by IATA code and by spelled-out name to its own reading")
    func everyCityResolvesByCodeAndByName() async throws {
        let tool = IntegrationWeatherTool()

        for city in integrationCityWeather {
            let byCode = try await tool.call(arguments: IntegrationWeatherArguments(city: city.code))
            let byName = try await tool.call(arguments: IntegrationWeatherArguments(city: city.name))

            #expect(byCode.tempC == city.tempC)
            #expect(byName.tempC == city.tempC)
        }
    }

    @Test("a city name inside a longer phrase still resolves to that one city")
    func aCityNameInsideALongerPhraseResolves() async throws {
        let city = integrationSingleCallCity

        let reading = try await IntegrationWeatherTool()
            .call(arguments: IntegrationWeatherArguments(city: "\(city.name) right now"))

        #expect(reading.tempC == city.tempC)
    }

    @Test("an unknown city throws instead of reporting some other city's reading")
    func anUnknownCityThrows() async throws {
        // A city no reading covers, and one no fixture edit can accidentally
        // introduce without this assertion failing loudly.
        let unknown = "Ulaanbaatar"
        #expect(!integrationCityWeather.contains { $0.name == unknown })

        await #expect(throws: IntegrationWeatherError.unknownCity(unknown)) {
            _ = try await IntegrationWeatherTool().call(arguments: IntegrationWeatherArguments(city: unknown))
        }
    }

    @Test("an argument naming several cities throws instead of answering for the first one")
    func aMultiCityArgumentThrows() async throws {
        // The exact shape that used to answer for whichever city came first
        // in itinerary order: a plausible reading for a city the caller never
        // singled out is the wrong-but-gradeable answer the throw prevents.
        let everyName = integrationCityWeather.map(\.name)
        let request = everyName.joined(separator: ", ")

        await #expect(throws: IntegrationWeatherError.ambiguousCity(request, matches: everyName)) {
            _ = try await IntegrationWeatherTool().call(arguments: IntegrationWeatherArguments(city: request))
        }
    }

    // MARK: - The two scenario questions stay two questions

    @Test("exactly one trip city is warmest, so the compose question has exactly one answer")
    func exactlyOneTripCityIsWarmest() {
        // The maximum is recomputed from the readings instead of read back off
        // `integrationWarmestCity.tempC`. Filtering the readings by the
        // warmest one's own temperature finds the warmest one whatever the
        // derivation did, so that spelling states the derivation back to
        // itself and cannot fail; a derivation that sorted the wrong way or
        // stopped at the runner-up fails this one.
        let hottest = integrationCityWeather.map(\.tempC).max()
        let warmest = integrationCityWeather.filter { $0.tempC == hottest }

        #expect(warmest.count == 1)
        #expect(warmest.first?.code == integrationWarmestCity.code)
    }

    @Test("the single-call scenario asks about a city that is not the warmest one")
    func theSingleCallCityIsNotTheWarmestCity() throws {
        // `integrationSingleCallCity` is derived as
        // `integrationCityWeather.first(where: { $0.code != integrationWarmestCity.code })`
        // (`ScenarioTools.swift`), so comparing it back against
        // `integrationWarmestCity.code` would only restate that exclusion —
        // guaranteed true by the derivation itself, and unable to fail without
        // editing that derivation. The hottest reading is recomputed here from
        // scratch instead, exactly as `exactlyOneTripCityIsWarmest` does, so a
        // bug shared between `integrationWarmestCity`'s sort and
        // `integrationSingleCallCity`'s exclusion (for example, if the sort
        // picked the wrong city and the exclusion inherited that mistake) is
        // still caught: the single-call city's own reading would then equal
        // the independently computed maximum.
        let hottest = try #require(integrationCityWeather.map(\.tempC).max())

        #expect(integrationSingleCallCity.tempC != hottest)
    }

    @Test("the single-call scenario grades the reading getWeather reports for its own city")
    func theSingleCallAnswerIsTheReadingTheToolReports() async throws {
        // Read back through the tool rather than off the fixture row: the
        // graded substring has to be the number a reply quoting `getWeather`
        // states. A matcher that resolved this city to a different reading,
        // or an answer set derived from a different city, leaves scenario 1
        // grading a temperature the model was never shown, and only the round
        // trip notices. The rendering here is deliberately the assertion's
        // own and not the fixture's `integrationTemperatureAnswer` — reusing
        // that helper would compare the answer set against the expression
        // that produced it.
        let reading = try await IntegrationWeatherTool()
            .call(arguments: IntegrationWeatherArguments(city: integrationSingleCallCity.name))

        #expect(IntegrationScenarioAnswers.singleCall == [String(Int(reading.tempC))])
    }

    @Test("the compose scenario grades the city its own getTrip-then-getWeather walk finds warmest")
    func theWarmestCityAnswersNameTheCityTheComposeWalkFinds() async throws {
        // The walk the compose and discovery scenarios ask a snippet to write,
        // run here in Swift: read the itinerary, read each city it lists, keep
        // the warmest. Grading the answer set against what that walk produces
        // is the part the set cannot check about itself — an itinerary and a
        // weather table that drifted apart, or answers derived from a city the
        // walk never reaches, fail here.
        //
        // Reading the set also runs `IntegrationScenarioAnswers`' own overlap
        // check, which traps on a substring relation between the two
        // scenarios' answers in either direction. That check is stricter than
        // any expectation here could be, and this suite is what makes it run
        // under an ungated `swift test`.
        let trip = try await IntegrationTripTool().call(arguments: IntegrationNoArguments(unused: nil))
        let weather = IntegrationWeatherTool()

        var readings: [(code: String, tempC: Double)] = []
        for code in trip.cities {
            let reading = try await weather.call(arguments: IntegrationWeatherArguments(city: code))
            readings.append((code: code, tempC: reading.tempC))
        }
        let warmest = try #require(readings.max { $0.tempC < $1.tempC })

        #expect(IntegrationScenarioAnswers.warmestCity.contains(warmest.code))
    }
}
