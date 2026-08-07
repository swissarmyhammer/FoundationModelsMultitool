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

        #expect(source.contains("cities: string[]"))
        #expect(source.contains("confirmationCode: string"))
        // The shape the reshape replaced. A snippet can consume that one
        // without reading the declaration at all, which is what made it a
        // weaker test of discovery.
        #expect(!source.contains("Promise<string[]>"))
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
        let warmest = integrationCityWeather.filter { $0.tempC == integrationWarmestCity.tempC }

        #expect(warmest.count == 1)
        #expect(warmest.first?.code == integrationWarmestCity.code)
    }

    @Test("the single-call scenario asks about a city that is not the warmest one")
    func theSingleCallCityIsNotTheWarmestCity() {
        #expect(integrationSingleCallCity.code != integrationWarmestCity.code)
    }

    @Test("neither scenario's graded answers can satisfy the other scenario's question")
    func theTwoScenariosGradeOnDisjointAnswers() {
        // Reading either set runs `IntegrationScenarioAnswers`' own
        // overlap check, which is stricter than this assertion: it rejects a
        // substring relation, not just an equal string. This test is what
        // makes that check run under an ungated `swift test`.
        let singleCall = Set(IntegrationScenarioAnswers.singleCall)
        let warmestCity = Set(IntegrationScenarioAnswers.warmestCity)

        #expect(!singleCall.isEmpty)
        #expect(!warmestCity.isEmpty)
        #expect(singleCall.isDisjoint(with: warmestCity))
    }

    @Test("the single-call scenario's graded substring reads back as the fixture's own reading")
    func theSingleCallAnswerReadsBackAsTheFixtureReading() {
        #expect(
            IntegrationScenarioAnswers.singleCall.allSatisfy { Double($0) == integrationSingleCallCity.tempC }
        )
    }
}
