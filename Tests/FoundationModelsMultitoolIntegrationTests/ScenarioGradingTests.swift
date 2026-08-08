import Testing

@testable import FoundationModelsMultitool

/// Ungated coverage for the verdict a gated scenario is graded on —
/// `scenarioChecks(for:answerContainsOneOf:answerMustNotContain:groundedIn:)`
/// in `Support/ScenarioRunner.swift`.
///
/// The grounding condition used to hold whenever *any* fixture call returned,
/// which is a weaker question than the one a scenario asks. Recorded on task
/// `0981ar3`, run 2 of the session-rule arm: the discovery scenario passed on a
/// run that fetched the itinerary, never fetched a temperature, and then named
/// the warmest city — an answer no run without a reading can know. The city
/// names alone satisfied "something returned".
///
/// So each scenario now declares what its answer depends on
/// (`IntegrationScenarioGrounding`), and this suite is where that declaration
/// is shown to discriminate: the recorded run is rebuilt from the fixtures and
/// must now fail, and a run that genuinely read the readings must still pass.
/// Both runs drive the real `MultiTool` a host mounts, so the log they are
/// graded on is written by the same `call(arguments:)` path a gated run takes.
///
/// Ungated on purpose, and for the same reason `ScenarioFixtureTests` is: the
/// grade itself only ever runs under `MULTITOOL_INTEGRATION`, so a grading rule
/// nobody can check from an ordinary `swift test` is a rule that rots — and this
/// one rotted unnoticed while the arms recorded on task `tkrdwb8` were measured
/// against it.
@Suite("Gated-scenario grading")
struct ScenarioGradingTests {
    // MARK: - The recorded false pass

    @Test("a run that fetched only the itinerary is not grounded, whichever city it names")
    func aTripOnlyRunThatNamesTheWarmestCityIsNotGrounded() async throws {
        let log = ScenarioCallLog()
        // The recorded shape: one snippet, one call, the city list and nothing
        // else. Written from the trip fixture's own path, so it cannot drift
        // into naming a function the mounted surface does not define.
        _ = try await Self.runComposeSnippet("return (await tools.\(IntegrationTripTool.path)()).cities;", log: log)
        #expect(await log.returnedPaths == [IntegrationTripTool.path])

        let checks = await Self.warmestCityChecks(typedPaths: [IntegrationTripTool.path], log: log)

        // The reply names the fixture's warmest city, so the answer's *form* is
        // valid — which is exactly why this run used to pass outright.
        let validAnswer = try Self.check(validAnswerCheckName, in: checks)
        #expect(validAnswer.held)
        // And it is not grounded: the reading the question turns on was never
        // fetched, so naming the right city was luck.
        let grounded = try Self.check(groundedCheckName, in: checks)
        #expect(!grounded.held)
    }

    // MARK: - The still-passes control

    @Test("a run that read the trip's readings is grounded")
    func aRunThatReadsEveryTripReadingIsGrounded() async throws {
        let log = ScenarioCallLog()
        // The walk the question actually needs: the itinerary, then a reading
        // for each city it lists.
        _ = try await Self.runComposeSnippet(
            """
            const trip = await tools.\(IntegrationTripTool.path)();
            const readings = await Promise.all(
                trip.cities.map((city) => tools.\(IntegrationWeatherTool.path)({ city: city }))
            );
            return readings.map((reading) => reading.tempC).join(",");
            """,
            log: log
        )
        #expect(await log.returnedPaths == IntegrationScenarioGrounding.warmestCity)

        let checks = await Self.warmestCityChecks(
            typedPaths: [IntegrationTripTool.path, IntegrationWeatherTool.path],
            log: log
        )

        let grounded = try Self.check(groundedCheckName, in: checks)
        #expect(grounded.held)
        // Nothing else broke either: the corrected rule is stricter about one
        // thing, not about everything.
        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed.isEmpty)
    }

    // MARK: - Every scenario declares something

    @Test("every gated scenario declares a non-empty dependency for its answer")
    func everyScenarioDeclaresWhatItsAnswerDependsOn() {
        // An empty declaration would grade every run as grounded, including one
        // that called nothing at all — the vacuous pass `scenarioChecks`
        // refuses, but only once a gated run reaches it.
        #expect(!IntegrationScenarioGrounding.singleCall.isEmpty)
        #expect(!IntegrationScenarioGrounding.warmestCity.isEmpty)
        #expect(!IntegrationScenarioGrounding.booking.isEmpty)
        #expect(!IntegrationScenarioGrounding.combinedStock.isEmpty)
    }

    // MARK: - Building the graded evidence

    /// Runs one snippet against the compose scenario's own two fixture tools.
    ///
    /// - Parameters:
    ///   - code: the snippet to run.
    ///   - log: the run's call log, which both fixtures record into.
    /// - Returns: the rendered `runCode` output.
    /// - Throws: whatever building the registry or calling `MultiTool` throws.
    private static func runComposeSnippet(_ code: String, log: ScenarioCallLog) async throws -> String {
        let registry = try MultiTool.Builder()
            .addTools([IntegrationTripTool(log: log), IntegrationWeatherTool(log: log)])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// Grades the compose and discovery scenarios' shared question against what `log` recorded.
    ///
    /// The reply, the accepted answers and the declared grounding all come from
    /// the fixtures, so this grades the same contract `SearchThenCallTests`'
    /// compose and discovery scenarios do rather than a copy of it.
    ///
    /// - Parameters:
    ///   - typedPaths: the `tools.*` paths the run's snippet wrote — the paths
    ///     the snippet above calls, which the grounding condition reports and
    ///     never grades on.
    ///   - log: the run's call log.
    /// - Returns: every graded condition, in reporting order.
    private static func warmestCityChecks(typedPaths: Set<String>, log: ScenarioCallLog) async -> [ScenarioCheck] {
        scenarioChecks(
            for: ScenarioEvidence(
                answer: replyNamingTheWarmestCity,
                typedPaths: typedPaths,
                invokedPaths: await log.invokedPaths,
                returnedPaths: await log.returnedPaths
            ),
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // Empty, exactly as the compose and discovery scenarios leave it.
            answerMustNotContain: [],
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }

    /// The reply both runs above are graded on: an answer to "which trip city is warmest", in the recorded shape.
    ///
    /// Rebuilt from the fixtures rather than quoted, so it names whichever city
    /// the readings make warmest instead of pinning the one the recorded run
    /// happened to name. The recorded reply opened by listing the trip's cities
    /// and then named one of them as the warmest, which is the whole difficulty:
    /// its *form* is a correct answer, and only what the run fetched separates
    /// it from one.
    private static var replyNamingTheWarmestCity: String {
        let itinerary = integrationCityWeather.map { "\($0.name) (\($0.code))" }.joined(separator: ", ")
        return "I can see your trip includes \(itinerary). \(integrationWarmestCity.name) is the warmest right now."
    }

    /// Picks one graded condition out of a run's verdict by name.
    ///
    /// - Parameters:
    ///   - name: the condition's label on the `SCENARIO` line.
    ///   - checks: every condition the run was graded on.
    /// - Returns: that condition.
    /// - Throws: an expectation failure when the verdict carries no condition of that name.
    private static func check(_ name: String, in checks: [ScenarioCheck]) throws -> ScenarioCheck {
        try #require(checks.first { $0.name == name })
    }
}
