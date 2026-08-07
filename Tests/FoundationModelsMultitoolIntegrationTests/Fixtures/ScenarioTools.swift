import FoundationModels

// MARK: - Scenario 1: single-call `weather` (plan.md M6.5 scenario 1)

/// `IntegrationWeatherTool`'s arguments.
@Generable
struct IntegrationWeatherArguments {
    @Guide(description: "IATA city code or city name.")
    var city: String
}

/// `IntegrationWeatherTool`'s output.
@Generable(description: "current conditions.")
struct IntegrationWeatherResult {
    var tempC: Double
    var summary: String
}

/// The one obvious tool scenario 1 asserts the model finds and calls,
/// rather than hallucinating an answer — plan.md M6.5 scenario 1.
struct IntegrationWeatherTool: Tool {
    let name = "weather"
    let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."

    func call(arguments: IntegrationWeatherArguments) async throws -> IntegrationWeatherResult {
        IntegrationWeatherResult(tempC: 31, summary: "Sunny")
    }
}

// MARK: - Scenario 2: compose/chain `tripCities` -> `weather` -> warmest (plan.md M6.5 scenario 2)

/// Arguments for a tool that takes nothing meaningful — every `Tool
/// .Arguments` must be an `object` schema, so an unused optional field
/// stands in for "no arguments", mirroring the main test target's own
/// `NoArguments` fixture (a distinct module, so redeclared here).
@Generable
struct IntegrationNoArguments {
    @Guide(description: "unused.")
    var unused: String?
}

/// `IntegrationTripCitiesTool`'s output.
@Generable
struct IntegrationTripCitiesOutput {
    var cities: [String]
}

/// The first half of the compose/chain scenario — plan.md's own worked
/// `tripCities(): string[]` example.
struct IntegrationTripCitiesTool: Tool {
    let name = "tripCities"
    let description = "The cities on the user's current trip, in itinerary order."

    func call(arguments: IntegrationNoArguments) async throws -> IntegrationTripCitiesOutput {
        IntegrationTripCitiesOutput(cities: ["ATX", "SFO", "NYC"])
    }
}

// MARK: - Scenario 3: discovery under ~20 distractors (plan.md M6.5 scenario 3)

/// Arguments every distractor tool shares — a single opaque `id`, just
/// enough shape to render a complete, callable-looking declaration without
/// any tool actually doing meaningful work.
@Generable
struct IntegrationDistractorArguments {
    @Guide(description: "an opaque id.")
    var id: String
}

/// The output every distractor tool shares.
@Generable
struct IntegrationDistractorOutput {
    var value: String
}

/// One generic, plausible-but-irrelevant distractor tool — plan.md M6.5
/// scenario 3: "~20 wrapped tools where only 2 are relevant." Each instance
/// is fully documented (a real name/description, not a stub) so the
/// completeness contract `ToolAPIRenderer`/`MultiTool.Builder.build()`
/// enforces is satisfied the same way a real third-party tool would be.
struct IntegrationDistractorTool: Tool {
    let name: String
    let description: String

    func call(arguments: IntegrationDistractorArguments) async throws -> IntegrationDistractorOutput {
        IntegrationDistractorOutput(value: "distractor:\(name):\(arguments.id)")
    }
}

/// 18 named, distinct distractor tools — combined with the 2 relevant tools
/// (`weather`, `tripCities`) the discovery scenario also wraps, the surface
/// totals ~20 tools, only 2 of which `findAPIs` should select.
let integrationDistractorTools: [any Tool] = [
    ("convertCurrency", "Converts an amount between two currencies."),
    ("bookHotel", "Books a hotel room for given dates."),
    ("cancelBooking", "Cancels an existing booking by id."),
    ("translateText", "Translates text between two languages."),
    ("sendEmail", "Sends an email to a recipient."),
    ("createCalendarEvent", "Creates a calendar event."),
    ("lookupFlight", "Looks up a flight's status by number."),
    ("convertUnits", "Converts a measurement between unit systems."),
    ("summarizeText", "Summarizes a block of text."),
    ("generateInvoice", "Generates an invoice PDF for an order."),
    ("trackPackage", "Tracks a shipment by tracking number."),
    ("checkStockPrice", "Looks up a stock's current price."),
    ("postToSocial", "Posts a message to a social feed."),
    ("scheduleReminder", "Schedules a reminder for later."),
    ("lookupRestaurant", "Finds restaurants near a location."),
    ("convertTimezone", "Converts a time between timezones."),
    ("queryDatabase", "Runs a read-only query against a database."),
    ("resizeImage", "Resizes an image to given dimensions."),
].map { name, description in
    IntegrationDistractorTool(name: name, description: description)
}

// MARK: - Scenario 4: repair from a trip-prone tool (plan.md M6.5 scenario 4)

/// `IntegrationBookingTool`'s arguments — `confirm` is a required boolean a
/// model summarizing "confirm this booking" often forgets to set at all,
/// tripping `ToolInvoker`'s argument-decoding validation on the first call.
@Generable
struct IntegrationBookingArguments {
    @Guide(description: "the booking id to confirm.")
    var id: Int

    @Guide(description: "must be set to true to actually confirm the booking.")
    var confirm: Bool
}

/// `IntegrationBookingTool`'s output.
@Generable
struct IntegrationBookingResult {
    var confirmed: Bool
}

/// Thrown by `IntegrationBookingTool.call` when a well-formed call
/// nonetheless passes `confirm: false` — `ToolInvoker`/`ResultRenderer` turn
/// this into the repairable error text fed back to the model, exercising the
/// same repair mechanics as an omitted `confirm` tripping decode validation.
enum IntegrationBookingError: Error, CustomStringConvertible {
    case confirmationRequired
    var description: String { "booking requires confirm: true" }
}

/// A deliberately trip-prone tool — plan.md M6.5 scenario 4: "a tool the
/// model tends to mis-call." Its description alone ("confirms a booking")
/// doesn't spell out that `confirm` must explicitly be `true`, so a model's
/// first attempt commonly omits `confirm` (tripping argument decoding) or
/// passes `false` (tripping this `call`'s own guard) — either way, the
/// resulting repairable error is exactly what the repair-loop scenario needs
/// to recover from.
struct IntegrationBookingTool: Tool {
    let name = "book"
    let description = "Confirms a trip booking by id."

    func call(arguments: IntegrationBookingArguments) async throws -> IntegrationBookingResult {
        guard arguments.confirm else {
            throw IntegrationBookingError.confirmationRequired
        }
        return IntegrationBookingResult(confirmed: true)
    }
}

// MARK: - Scenario 5: elevation in code mode (eventplan.md phase-1 exit)

/// `IntegrationDeepScanTool`'s output.
@Generable(description: "a completed scan's report code.")
struct IntegrationDeepScanOutput {
    var reportCode: Int
}

/// How long `IntegrationDeepScanTool` works before it reports.
///
/// Chosen to sit between the two clocks Router's native session mount arms a
/// `runCode` call with (`ElevationConfiguration.nativeSessionMount`): longer
/// than its 5-second `defaultWaitSeconds`, so the outer `runCode` call that
/// awaits this tool always outlives its wait window and elevates into a
/// pending envelope; and far shorter than its 120-second
/// `defaultTimeoutSeconds` (and than `MultiToolConfiguration
/// .executionTimeLimit`, the sandbox watchdog's absolute ceiling), so the
/// parked run settles on its own while the model is still composing the
/// follow-up that collects it.
let integrationDeepScanDuration: Duration = .seconds(8)

/// The report code `IntegrationDeepScanTool` always returns.
///
/// A *code*, deliberately, and not a count of anything. An earlier version of
/// this fixture reported "how many findings" the scan turned up, and the model
/// repeatedly answered "42 findings" out of thin air without ever running the
/// scan — a count of an unspecified thing is a question a model is happy to
/// make up. It has no such prior for the report code of a scan of the user's
/// own archive: that is a value it plainly cannot know, so the only way to it
/// is to run the scan and collect the parked run — which is the whole point of
/// the scenario.
let integrationDeepScanReportCode = 41739

/// The deliberately slow tool the elevation scenario drives: a snippet that
/// awaits it cannot finish inside the mount's wait window, so the outer
/// `runCode` call hands the model a pending envelope and keeps running in the
/// background. Recovering the answer then requires the run-plane globals
/// (`status()`, `wait(completionToken, seconds)`) the sandbox installs — which
/// is exactly the round trip eventplan.md's phase 1 has to prove end to end.
struct IntegrationDeepScanTool: Tool {
    let name = "deepScan"
    let description = "Runs a full deep scan of the user's archive and returns that scan's report code. "
        + "The scan takes several seconds to complete."

    func call(arguments: IntegrationNoArguments) async throws -> IntegrationDeepScanOutput {
        try await Task.sleep(for: integrationDeepScanDuration)
        return IntegrationDeepScanOutput(reportCode: integrationDeepScanReportCode)
    }
}

// MARK: - Scenario 6: async fan-out over two independent tools

/// The output both halves of the fan-out pair report.
@Generable(description: "a stock count, in units.")
struct IntegrationStockCount {
    var units: Int
}

/// One stock counter — a named, fully-described tool that reports a fixed
/// number of units.
///
/// Two instances make up the async fan-out scenario's pair. Neither depends on
/// the other, so the natural snippet reads both at once (`Promise.all`) rather
/// than chaining them, and only their sum answers the question — which is what
/// makes the combined total a grounded assertion.
struct IntegrationStockTool: Tool {
    let name: String
    let description: String

    /// The unit count this counter always reports.
    let units: Int

    func call(arguments: IntegrationNoArguments) async throws -> IntegrationStockCount {
        IntegrationStockCount(units: units)
    }
}

/// The warehouse half of the async fan-out pair.
let integrationWarehouseStockTool = IntegrationStockTool(
    name: "warehouseStock",
    description: "How many units of the product are in the warehouse right now.",
    units: 1904
)

/// The store-floor half of the async fan-out pair.
let integrationStoreStockTool = IntegrationStockTool(
    name: "storeStock",
    description: "How many units of the product are on the store floor right now.",
    units: 268
)
