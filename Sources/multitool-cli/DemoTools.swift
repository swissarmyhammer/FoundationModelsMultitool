import FoundationModels

/// Arguments shared by every tool in this sample that takes no meaningful
/// input — every `Tool.Arguments` must be an `object` schema, so an unused
/// optional field stands in for "no arguments," mirroring this package's own
/// test fixtures (e.g.
/// `Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolExecutionFixtures.swift`'s
/// `NoArguments`).
@Generable
struct DemoNoArguments {
    /// Unused; present only so this type renders as a non-empty `object` schema.
    @Guide(description: "unused.")
    var unused: String?
}

/// `DemoTripCitiesTool`'s output — plan.md's own worked `tripCities():
/// string[]` example.
@Generable
struct DemoTripCitiesOutput {
    /// The itinerary's cities, in visit order.
    var cities: [String]
}

/// A small, fixed itinerary — one of the two demo tools `CLIRunner` wraps
/// into the sample's `MultiTool` registry (driven by a native
/// `LanguageModelSession`), chosen (together with `DemoWeatherTool`) to
/// trigger the compose/chain behavior plan.md's own usage example walks
/// through: `tripCities` -> `weather` per city -> pick the warmest.
struct DemoTripCitiesTool: Tool {
    let name = "tripCities"
    let description = "The cities on the user's current trip, in itinerary order."

    /// Returns the sample's fixed itinerary.
    ///
    /// - Parameter arguments: unused.
    /// - Returns: the fixed itinerary.
    func call(arguments: DemoNoArguments) async throws -> DemoTripCitiesOutput {
        DemoTripCitiesOutput(cities: ["ATX", "SFO", "NYC"])
    }
}

/// `DemoWeatherTool`'s arguments.
@Generable
struct DemoWeatherArguments {
    /// The city to look up.
    @Guide(description: "IATA city code or city name.")
    var city: String
}

/// `DemoWeatherTool`'s output.
@Generable(description: "current conditions.")
struct DemoWeatherResult {
    /// The current temperature, in Celsius.
    var tempC: Double
    /// A short human-readable summary, e.g. "Sunny".
    var summary: String
}

/// A fixed-fixture weather lookup — the sample's second demo tool.
/// Deterministic (no live weather API) so the demo's "warmest city" prompt
/// always has one unambiguous right answer.
struct DemoWeatherTool: Tool {
    let name = "weather"
    let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."

    /// Deterministic per-city temperatures, keyed by `DemoTripCitiesTool`'s
    /// itinerary codes, so the demo's "which is warmest" prompt has one
    /// unambiguous answer (Austin).
    private static let temperaturesByCity: [String: Double] = [
        "ATX": 31,
        "SFO": 18,
        "NYC": 24,
    ]

    /// Looks up the fixed temperature for `arguments.city`.
    ///
    /// - Parameter arguments: the city to look up.
    /// - Returns: that city's fixed conditions, or a generic 20°C fallback
    ///   for a city outside the fixed table.
    func call(arguments: DemoWeatherArguments) async throws -> DemoWeatherResult {
        let tempC = Self.temperaturesByCity[arguments.city] ?? 20
        return DemoWeatherResult(tempC: tempC, summary: "Sunny")
    }
}
