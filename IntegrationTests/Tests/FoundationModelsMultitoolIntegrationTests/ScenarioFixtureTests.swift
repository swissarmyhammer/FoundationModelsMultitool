import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// Ungated coverage for the premises the gated scenarios grade on
/// (`Fixtures/ScenarioTools.swift`).
///
/// Every assertion in `SearchThenCallTests` rests on something being true of
/// those fixtures — that exactly one trip city is warmest, that the trip tool
/// forces a snippet to navigate to `.cities`, that `getWeather` refuses an
/// argument it cannot resolve to one city, that no single reply can answer
/// both scenario questions. All four scenarios run only against a real model
/// on capable hardware, so until this suite existed a fixture edit could
/// break any of those premises and leave every check anyone could actually run
/// green while those assertions quietly stopped meaning what they say.
///
/// The same holds for the fixtures' own call log: the gated runners grade on
/// what `ScenarioCallLog` recorded, so its recording rules are exercised here
/// too.
///
/// These tests carry no gate on purpose. They need no model, no download and
/// no GPU: they render the surface and run snippets through the same
/// `MultiTool` a host mounts, and read the fixtures directly.
@Suite("Gated-scenario fixture premises")
struct ScenarioFixtureTests {
    // MARK: - The trip tool's object shape

    @Test("the trip tool renders as a multi-field object rather than a bare list of cities")
    func tripToolRendersAsAMultiFieldObject() throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool(log: ScenarioCallLog())).buildRegistry()

        let source = registry.surface.source

        // The rendered return type in full, rather than a sample of two of
        // its fields: the reshape buys nothing unless the declaration a model
        // reads names every sibling, so dropping one, renaming one or
        // reordering them all fail here.
        //
        // The shape this replaced is `Promise<{ cities: string[] }>` — an
        // object already, so `.cities` navigation is not what changed; the
        // four siblings are, and a single-field object is one a snippet can
        // consume without reading the declaration at all.
        //
        // A bare `Promise<string[]>` is not asserted absent here, and the
        // renderer is not the reason it cannot appear: `ToolAPIRenderer`
        // requires an object schema of a tool's `parameters` only, never of
        // its return, and `[String]` is itself `Generable`, so a tool
        // returning one takes the schema branch and its array root renders
        // `string[]`. A non-`Generable` `Output` takes the `.text` branch
        // and renders `Promise<string>` — the `echoText` fixture in the main
        // target's `BuilderSurface.ts.txt` golden. What rules the bare list
        // out is local to this test: the registry holds `IntegrationTripTool`
        // alone, whose `Output` is the five-field `IntegrationTripOutput`.
        // The expectation below states that shape rather than guessing at
        // which others the renderer could not have produced.
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
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool(log: ScenarioCallLog())).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return (await tools.getTrip()).cities.join("-");"#)
        )

        #expect(output == "\"\(integrationCityWeather.map(\.code).joined(separator: "-"))\"")
    }

    @Test("a snippet that treats the whole trip result as the city list gets a repairable error")
    func tripSnippetThatSkipsCitiesFails() async throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool(log: ScenarioCallLog())).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: #"return (await tools.getTrip()).join("-");"#)
        )

        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
    }

    // MARK: - `getWeather` resolves exactly one city, or refuses

    @Test("every fixture city resolves by IATA code and by spelled-out name to its own reading")
    func everyCityResolvesByCodeAndByName() async throws {
        let tool = IntegrationWeatherTool(log: ScenarioCallLog())

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

        let reading = try await IntegrationWeatherTool(log: ScenarioCallLog())
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
            _ = try await IntegrationWeatherTool(log: ScenarioCallLog())
                .call(arguments: IntegrationWeatherArguments(city: unknown))
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
            _ = try await IntegrationWeatherTool(log: ScenarioCallLog())
                .call(arguments: IntegrationWeatherArguments(city: request))
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
        let reading = try await IntegrationWeatherTool(log: ScenarioCallLog())
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
        let log = ScenarioCallLog()
        let trip = try await IntegrationTripTool(log: log).call(arguments: IntegrationNoArguments(unused: nil))
        let weather = IntegrationWeatherTool(log: log)

        var readings: [(code: String, tempC: Double)] = []
        for code in trip.cities {
            let reading = try await weather.call(arguments: IntegrationWeatherArguments(city: code))
            readings.append((code: code, tempC: reading.tempC))
        }
        let warmest = try #require(readings.max { $0.tempC < $1.tempC })

        #expect(IntegrationScenarioAnswers.warmestCity.contains(warmest.code))
    }

    // MARK: - What the fixture tools recorded actually running

    @Test("a fresh call log has recorded nothing")
    func aFreshCallLogHasRecordedNothing() async {
        let log = ScenarioCallLog()

        #expect(await log.calls.isEmpty)
        #expect(await log.invokedPaths.isEmpty)
        #expect(await log.returnedPaths.isEmpty)
    }

    @Test("a fixture tool that hands a value back records an invocation that returned")
    func aToolThatHandsAValueBackRecordsAReturnedInvocation() async throws {
        let log = ScenarioCallLog()
        let tool = IntegrationWeatherTool(log: log)

        _ = try await tool.call(arguments: IntegrationWeatherArguments(city: integrationSingleCallCity.name))

        #expect(await log.calls == [ScenarioCall(path: tool.name, outcome: .returned)])
        #expect(await log.invokedPaths == [tool.name])
        #expect(await log.returnedPaths == [tool.name])
    }

    @Test("a fixture tool that throws records an invocation that never returned")
    func aToolThatThrowsRecordsAnInvocationThatNeverReturned() async throws {
        let log = ScenarioCallLog()
        let tool = IntegrationWeatherTool(log: log)

        await #expect(throws: IntegrationWeatherError.self) {
            _ = try await tool.call(arguments: IntegrationWeatherArguments(city: "Ulaanbaatar"))
        }

        // Entered, so it is an invocation; it handed nothing back, so it
        // grounds nothing — the whole point of keeping the two apart.
        #expect(await log.calls == [ScenarioCall(path: tool.name, outcome: .threw)])
        #expect(await log.invokedPaths == [tool.name])
        #expect(await log.returnedPaths.isEmpty)
    }

    @Test("every call of a snippet that awaits two tools at once is recorded")
    func concurrentCallsThroughOneSnippetAreAllRecorded() async throws {
        // `Promise.all` over two independent tools is the async fan-out
        // scenario's own natural snippet, so the log really is written from
        // two calls in flight at the same time.
        let log = ScenarioCallLog()
        let counters = integrationStockTools(log: log)
        let registry = try MultiTool.Builder().addTools(counters).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let calls = counters.map { "tools.\($0.name)()" }.joined(separator: ", ")

        let output = try await multiTool.call(
            arguments: RunCodeArguments(
                code: """
                    const counts = await Promise.all([\(calls)]);
                    return counts.reduce((total, count) => total + count.units, 0);
                    """
            )
        )

        // A total reduced from the two counts shares no text with either of
        // them, so the run closes with `ToolReturnLedger`'s notice as well —
        // the fan-out snippet is a real instance of the shape that detector
        // reports on, and a gated model writing this snippet reads the same
        // sentence. The whole output is compared, and the notice is read from
        // its one source rather than restated (task `wnfzwxg`).
        let total = integrationWarehouseStockUnits + integrationStoreStockUnits
        #expect(output == "\(total)\n\n\(ToolReturnLedger.uncarriedReturnNotice)")
        #expect(await log.calls.count == counters.count)
        #expect(await log.invokedPaths == Set(counters.map(\.name)))
        #expect(await log.returnedPaths == Set(counters.map(\.name)))
    }

    @Test("a snippet naming paths no fixture defines invokes nothing, though the scan still reports what it typed")
    func aSnippetNamingPathsNoFixtureDefinesInvokesNothing() async throws {
        // The recorded false pass this split exists to remove (task
        // `0981ar3`): a compose run whose snippet called two names the mounted
        // surface did not define scored `grounded=pass`, because the grade was
        // read off the snippet's source text. Both calls threw; nothing ran;
        // the temperature in the reply came from nowhere.
        let log = ScenarioCallLog()
        let registry = try MultiTool.Builder().addTool(IntegrationWeatherTool(log: log)).buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let code = #"""
            const trip = await tools.getItinerary();
            return (await tools.getForecast({ city: trip.cities[0] })).tempC;
            """#

        let output = try await multiTool.call(arguments: RunCodeArguments(code: code))

        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
        #expect(await log.invokedPaths.isEmpty)
        #expect(await log.returnedPaths.isEmpty)
        // The lexical scan still answers its own question — which names the
        // model wrote — because that is the only place an invented path is
        // visible at all, and it is what `inventedPath` is counted from.
        #expect(
            NativeTranscript.typedToolPaths(in: Self.transcriptRunning(code)) == ["getItinerary", "getForecast"]
        )
    }

    // MARK: - The fixture the in-band collection canary drives

    @Test("the archive-rebuild fixture reports its manifest code")
    func theRebuildFixtureReportsItsManifestCode() async throws {
        // The premise the canary's grounding rests on: the manifest code
        // reaches the model through this return and through nothing else, so a
        // fixture that stopped reporting it would make every gated grounding
        // assertion fail on a cause an ordinary `swift test` never named.
        let log = ScenarioCallLog()

        let rebuild = try await IntegrationArchiveRebuildTool(log: log)
            .call(arguments: IntegrationNoArguments(unused: nil))

        #expect(rebuild.manifestCode == integrationArchiveRebuildManifestCode)
        #expect(await log.returnedPaths == [IntegrationArchiveRebuildTool.path])
    }

    @Test("the in-band collection canary's manifest code answers no other scenario's question")
    func theManifestCodeAnswersNoOtherScenarioQuestion() {
        // The same rule `IntegrationScenarioAnswers` enforces between its own
        // two answer sets, extended to the two code-shaped fixtures that came
        // later. A manifest code that contained — or was contained by — the deep
        // scan's report code would let a reply about the wrong run satisfy this
        // scenario, and both are `answerContainsOneOf` substring matches.
        let manifest = integerAnswers(for: integrationArchiveRebuildManifestCode)
        let everyOtherAnswer = integerAnswers(for: integrationDeepScanReportCode)
            + integerAnswers(for: integrationWarehouseStockUnits + integrationStoreStockUnits)
            + IntegrationScenarioAnswers.singleCall
            + IntegrationScenarioAnswers.warmestCity

        for answer in manifest {
            for other in everyOtherAnswer {
                #expect(!answer.localizedCaseInsensitiveContains(other))
                #expect(!other.localizedCaseInsensitiveContains(answer))
            }
        }
    }

    /// Builds the transcript shape `NativeTranscript.typedToolPaths(in:)` scans: one recorded `runCode` call carrying a snippet.
    ///
    /// - Parameter code: the snippet the recorded call carries.
    /// - Returns: a transcript holding that one tool call and nothing else.
    private static func transcriptRunning(_ code: String) -> Transcript {
        Transcript(entries: [
            .toolCalls(
                Transcript.ToolCalls([
                    Transcript.ToolCall(
                        id: "1",
                        toolName: "runCode",
                        arguments: GeneratedContent(properties: ["code": code])
                    )
                ])
            )
        ])
    }
}
