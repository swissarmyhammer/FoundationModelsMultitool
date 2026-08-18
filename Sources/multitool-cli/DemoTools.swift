import FoundationModels

/// Arguments for a demo tool that takes no meaningful input.
///
/// Every `Tool.Arguments` must be an `object` schema, so an unused optional
/// field stands in for "no arguments," mirroring this package's own test
/// fixtures (e.g.
/// `Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolExecutionFixtures.swift`'s
/// `NoArguments`).
@Generable
struct DemoNoArguments {
    /// Unused; present only so this type renders as a non-empty `object` schema.
    @Guide(description: "unused.")
    var unused: String?
}

/// The cities on the trip, in visit order.
@Generable
struct DemoTripOutput {
    /// The itinerary's cities, in visit order.
    var cities: [String]
}

/// A fixed-fixture itinerary lookup, the sample's first demo tool.
///
/// One of the two demo tools `CLIRunner` wraps into the sample's `MultiTool`
/// registry, driven by the `RoutedSession` the resolved profile vends. Chosen
/// together with
/// `DemoWeatherTool` to trigger the compose/chain behavior plan.md's own usage
/// example walks through: `getTrip` -> `getWeather` per city -> pick the
/// warmest.
struct DemoTripTool: Tool {
    /// The name the model calls this tool by.
    let name = "getTrip"
    /// The one-line capability blurb the model selects this tool from.
    let description = "The cities on the user's current trip, in itinerary order."

    /// Returns the sample's fixed itinerary.
    ///
    /// - Parameter arguments: unused.
    /// - Throws: Never; the `throws` comes from `Tool`'s requirement.
    /// - Returns: the fixed itinerary.
    func call(arguments: DemoNoArguments) async throws -> DemoTripOutput {
        DemoTripOutput(cities: ["ATX", "SFO", "NYC"])
    }
}

/// The arguments a weather lookup takes.
@Generable
struct DemoWeatherArguments {
    /// The city to look up.
    @Guide(description: "IATA city code or city name.")
    var city: String
}

/// A city's current temperature and a short summary of its conditions.
@Generable(description: "current conditions.")
struct DemoWeatherResult {
    /// The current temperature, in Celsius.
    var temperatureCelsius: Double
    /// A short human-readable summary, e.g. "Sunny".
    var summary: String
}

/// A fixed-fixture weather lookup, the sample's second demo tool.
///
/// Deterministic, with no live weather API, so the demo's "warmest city"
/// prompt has one unambiguous right answer.
struct DemoWeatherTool: Tool {
    /// The name the model calls this tool by.
    let name = "getWeather"
    /// The one-line capability blurb the model selects this tool from.
    let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."

    /// The warmest of ``temperaturesByCity``'s three readings, in Celsius.
    ///
    /// Austin's reading, and the largest of the three, so the demo's "which is
    /// warmest" prompt has one unambiguous answer.
    private static let warmestTemperatureCelsius: Double = 31

    /// The middle of ``temperaturesByCity``'s three readings, in Celsius.
    ///
    /// New York City's reading, between the other two.
    private static let middleTemperatureCelsius: Double = 24

    /// The coolest of ``temperaturesByCity``'s three readings, in Celsius.
    ///
    /// San Francisco's reading, the smallest of the three.
    private static let coolestTemperatureCelsius: Double = 18

    /// Deterministic per-city temperatures, keyed by `DemoTripTool`'s itinerary codes.
    ///
    /// Austin's is the largest, so the demo's "which is warmest" prompt has one
    /// unambiguous answer.
    private static let temperaturesByCity: [String: Double] = [
        "ATX": warmestTemperatureCelsius,
        "SFO": coolestTemperatureCelsius,
        "NYC": middleTemperatureCelsius,
    ]

    /// The Celsius temperature reported for a city outside ``temperaturesByCity``.
    ///
    /// Below ``warmestTemperatureCelsius``, so a city off the itinerary does
    /// not read warmer than Austin.
    private static let fallbackTemperatureCelsius: Double = 20

    /// Looks up the fixed temperature for `arguments.city`.
    ///
    /// - Parameter arguments: the lookup's arguments, carrying the city to read.
    /// - Throws: Never; the `throws` comes from `Tool`'s requirement.
    /// - Returns: that city's fixed conditions, falling back to
    ///   ``fallbackTemperatureCelsius`` for a city outside the fixed table.
    func call(arguments: DemoWeatherArguments) async throws -> DemoWeatherResult {
        let temperatureCelsius = Self.temperaturesByCity[arguments.city] ?? Self.fallbackTemperatureCelsius
        return DemoWeatherResult(temperatureCelsius: temperatureCelsius, summary: "Sunny")
    }
}
