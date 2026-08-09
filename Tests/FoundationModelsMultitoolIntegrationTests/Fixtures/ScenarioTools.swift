import FoundationModels

// MARK: - Scenario 1: single-call `getWeather` (plan.md M6.5 scenario 1)

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

/// One trip city's fixture weather reading.
struct IntegrationCityWeather {
    /// The IATA code `IntegrationTripTool` reports this city by.
    let code: String

    /// The city's spelled-out name, which models routinely expand codes to.
    let name: String

    /// The city's temperature, in °C.
    let tempC: Double
}

/// The trip cities' fixture weather readings, in itinerary order.
///
/// Distinct per city, deliberately. One constant reading for every city leaves
/// "which is warmest?" with three equally correct answers, so a scenario that
/// accepts any of them grades a three-way tie as a pass — the unearned pass the
/// human ruling of 2026-08-07 on task `tkrdwb8` called out. With these readings
/// the question has exactly one answer.
///
/// San Francisco is the warmest, and that is the point: on a trip that also
/// visits Austin it is not the answer priors alone give, so naming it is
/// evidence the snippet really read the readings. Which city scenario 1 asks
/// about follows from the same table rather than being fixed here: it is
/// `integrationSingleCallCity`, the first reading below that is not the
/// warmest one. Raising a temperature therefore moves that scenario onto
/// another city instead of leaving it grading a reading that stopped being
/// the one it asks about.
let integrationCityWeather: [IntegrationCityWeather] = [
    IntegrationCityWeather(code: "ATX", name: "Austin", tempC: 31),
    IntegrationCityWeather(code: "SFO", name: "San Francisco", tempC: 34),
    IntegrationCityWeather(code: "NYC", name: "New York", tempC: 22),
]

/// The single warmest trip city — the one correct answer to the compose/chain
/// and discovery scenarios' shared question.
///
/// Derived from `integrationCityWeather` rather than restated, so an assertion
/// built on it cannot drift from the readings it grades.
///
/// The derivation enforces the uniqueness the question depends on instead of
/// assuming it. `max(by:)` answers a tie by returning one of the tied cities,
/// which would leave "which is warmest?" with more than one correct answer
/// while the assertion still looked derived — the unearned pass the human
/// ruling of 2026-08-07 on task `tkrdwb8` removed. A fixture edit that
/// reintroduces a tie now traps here.
let integrationWarmestCity: IntegrationCityWeather = {
    let byDescendingTemperature = integrationCityWeather.sorted { $0.tempC > $1.tempC }
    precondition(
        byDescendingTemperature.count >= 2,
        "integrationCityWeather needs at least two readings for \"which is warmest?\" to be a question"
    )
    precondition(
        byDescendingTemperature[0].tempC > byDescendingTemperature[1].tempC,
        """
        integrationCityWeather ties for warmest at \(byDescendingTemperature[0].tempC) °C \
        (\(byDescendingTemperature[0].code) and \(byDescendingTemperature[1].code)); the compose and \
        discovery scenarios grade on there being exactly one warmest trip city
        """
    )
    return byDescendingTemperature[0]
}()

/// The trip city scenario 1 asks about by name, and whose own reading that
/// scenario grades on.
///
/// The first reading that is not `integrationWarmestCity`, derived rather than
/// named. Scenario 1's answer must not double as the compose and discovery
/// scenarios' answer, and the warmest city's reading would: a reply naming
/// that city and its temperature would satisfy both questions at once.
/// Deriving the city means raising its temperature past every other reading
/// moves scenario 1 onto a different city, instead of silently collapsing the
/// two questions into one.
let integrationSingleCallCity: IntegrationCityWeather = {
    guard let city = integrationCityWeather.first(where: { $0.code != integrationWarmestCity.code }) else {
        preconditionFailure("integrationCityWeather has no reading other than the warmest one")
    }
    return city
}()

/// Renders a fixture reading's temperature as the substring a reply states it
/// with.
///
/// - Parameter tempC: the reading, in °C.
/// - Returns: `tempC` as a whole number, with no decimal point.
private func integrationTemperatureAnswer(_ tempC: Double) -> String {
    precondition(
        tempC == tempC.rounded(),
        "fixture reading \(tempC) °C is not a whole number, so no whole-number substring grades it"
    )
    return String(Int(tempC))
}

/// The substrings the gated scenarios accept as answers to their two
/// questions.
///
/// Both sets are derived from `integrationCityWeather`, and derived *together*
/// so their distinctness is enforced rather than incidental. The two questions
/// are only different questions while no reply can answer both: with
/// hand-written literals the sets happened not to overlap, and raising one
/// reading past the others would have made scenario 1's temperature and the
/// warmest-city answer describe the same city without anything noticing. The
/// derivation below traps on any overlap.
enum IntegrationScenarioAnswers {
    /// The only valid answers to scenario 1's question, "how warm is it in
    /// `integrationSingleCallCity`": that city's own reading.
    static let singleCall = derived.singleCall

    /// The only valid answers to the compose/chain and discovery scenarios'
    /// shared question, "which trip city is warmest": the single warmest
    /// fixture city, by IATA code and by the spelled-out name models routinely
    /// expand codes to. Any other city is wrong.
    static let warmestCity = derived.warmestCity

    /// Both answer sets, derived in one place so the distinctness check below
    /// runs whenever either set is read.
    private static let derived: (singleCall: [String], warmestCity: [String]) = {
        let singleCall = [integrationTemperatureAnswer(integrationSingleCallCity.tempC)]
        let warmestCity = [integrationWarmestCity.code, integrationWarmestCity.name]
        let collisions = singleCall.flatMap { answer in
            warmestCity
                .filter { $0.lowercased().contains(answer.lowercased()) || answer.lowercased().contains($0.lowercased()) }
                .map { "\"\(answer)\" and \"\($0)\"" }
        }
        precondition(
            collisions.isEmpty,
            """
            the gated scenarios' graded answers overlap (\(collisions.joined(separator: ", "))): one reply \
            would satisfy both questions, so neither scenario would grade the question it asks
            """
        )
        return (singleCall, warmestCity)
    }()
}

/// Thrown by `IntegrationWeatherTool.call` when an argument does not single
/// out exactly one fixture reading.
///
/// A real weather API rejects a city it cannot resolve rather than inventing a
/// reading, and these scenarios need that: a silent fallback temperature would
/// let a snippet that passed the wrong argument still produce a number, and a
/// number is exactly what the answer assertions grade.
///
/// Both cases close that hole, from the two directions an argument can miss.
/// `.unknownCity` is the empty side. `.ambiguousCity` is the crowded side, and
/// it is the one this fixture used to get wrong: matching took the first
/// reading in itinerary order whose name appeared in the argument, so
/// `"Austin, San Francisco, New York"` quietly answered for Austin. A caller
/// that names several cities has singled out none of them, and a plausible
/// reading for one of them is exactly the kind of wrong-but-gradeable answer
/// the throw exists to prevent.
///
/// `Equatable` so the ungated `ScenarioFixtureTests` can assert *which* refusal
/// a bad argument earns, rather than only that some error was thrown — the two
/// cases describe different defects and a test that conflates them would pass
/// while one of them regressed into the other.
enum IntegrationWeatherError: Error, Equatable, CustomStringConvertible {
    /// No fixture reading matches the requested city.
    case unknownCity(String)

    /// The requested city matches more than one fixture reading, named here.
    case ambiguousCity(String, matches: [String])

    var description: String {
        let known = integrationCityWeather.map { "\($0.code) (\($0.name))" }.joined(separator: ", ")
        switch self {
        case .unknownCity(let city):
            return "no weather reading for \"\(city)\"; known cities are \(known)"
        case .ambiguousCity(let city, let matches):
            return "\"\(city)\" names \(matches.count) cities (\(matches.joined(separator: ", "))); "
                + "ask for one city at a time. Known cities are \(known)"
        }
    }
}

/// Reduces a city code or name to the form the fixture readings match on.
///
/// - Parameter city: the code or name exactly as the snippet passed it.
/// - Returns: `city` lowercased, with every non-letter removed.
private func integrationCityKey(_ city: String) -> String {
    city.lowercased().filter(\.isLetter)
}

/// The one obvious tool scenario 1 asserts the model finds and calls,
/// rather than hallucinating an answer — plan.md M6.5 scenario 1.
struct IntegrationWeatherTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level so a scenario can name the path its answer
    /// depends on — see `IntegrationScenarioGrounding` — without spelling the
    /// string a second time somewhere a rename would not reach.
    static let path = "getWeather"

    let name = IntegrationWeatherTool.path
    let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Reports the fixture reading for the one city `arguments` names.
    ///
    /// An argument resolves when it is exactly a city's code or exactly its
    /// name (`"ATX"`, `"Austin"`), or when it spells that name inside a longer
    /// phrase (`"San Francisco, CA"`). A three-letter code is matched only
    /// exactly — short enough that containment would find one by accident in
    /// unrelated text.
    ///
    /// Both refusals below are recorded as invocations that did not return:
    /// the snippet really did reach this tool, and got an error back rather
    /// than a reading.
    ///
    /// - Parameter arguments: the requested city.
    /// - Returns: that city's fixture reading.
    /// - Throws: `IntegrationWeatherError.unknownCity` when no reading
    ///   resolves, `IntegrationWeatherError.ambiguousCity` when more than one
    ///   does.
    func call(arguments: IntegrationWeatherArguments) async throws -> IntegrationWeatherResult {
        try await log.recordCall(to: name) {
            let requested = integrationCityKey(arguments.city)
            let matches = integrationCityWeather.filter { city in
                let cityName = integrationCityKey(city.name)
                return requested == integrationCityKey(city.code) || requested == cityName
                    || requested.contains(cityName)
            }
            guard let city = matches.first else {
                throw IntegrationWeatherError.unknownCity(arguments.city)
            }
            guard matches.count == 1 else {
                throw IntegrationWeatherError.ambiguousCity(arguments.city, matches: matches.map(\.name))
            }
            return IntegrationWeatherResult(tempC: city.tempC, summary: "Sunny")
        }
    }
}

// MARK: - Scenario 2: compose/chain `getTrip` -> `getWeather` -> warmest (plan.md M6.5 scenario 2)

/// Arguments for a tool that takes nothing meaningful — every `Tool
/// .Arguments` must be an `object` schema, so an unused optional field
/// stands in for "no arguments", mirroring the main test target's own
/// `NoArguments` fixture (a distinct module, so redeclared here).
@Generable
struct IntegrationNoArguments {
    @Guide(description: "unused.")
    var unused: String?
}

/// `IntegrationTripTool`'s output — a whole trip, not just its cities.
///
/// Carries the trip's own booking fields alongside its cities, the way a real
/// itinerary API answers, so a snippet has to read the declared shape and
/// navigate to `.cities` rather than guess.
///
/// What the human ruling of 2026-08-07 on task `tkrdwb8` changed here is the
/// four sibling fields, not the navigation. The type this replaced was already
/// an object — `IntegrationTripCitiesOutput`, whose single field was `cities`
/// — so a snippet already had to write `.cities`; it rendered as `{ cities:
/// string[] }`, where the one field is the only thing it could possibly be and
/// naming it costs no reading. Five fields make the declaration something a
/// snippet has to consult.
@Generable(description: "the user's current trip.")
struct IntegrationTripOutput {
    var confirmationCode: String
    var traveler: String
    var startDate: String
    var endDate: String
    var cities: [String]
}

/// The first half of the compose/chain scenario.
struct IntegrationTripTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level for the same reason as
    /// `IntegrationWeatherTool.path`: the compose and discovery scenarios name
    /// it in what their answer depends on.
    static let path = "getTrip"

    let name = IntegrationTripTool.path
    let description = "The user's current trip: its cities in itinerary order, plus its dates, "
        + "its traveler and its booking confirmation code."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Reports the fixture itinerary.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: the fixture trip.
    /// - Throws: nothing of its own; the signature is `Tool`'s, and
    ///   `recordCall(to:_:)` only rethrows what its body throws.
    func call(arguments: IntegrationNoArguments) async throws -> IntegrationTripOutput {
        await log.recordCall(to: name) {
            IntegrationTripOutput(
                confirmationCode: "QX7T2M",
                traveler: "Dana Whitfield",
                startDate: "2026-09-14",
                endDate: "2026-09-21",
                // Derived from the weather readings, so the itinerary and the
                // temperatures a snippet looks up can never name different cities.
                cities: integrationCityWeather.map(\.code)
            )
        }
    }
}

// MARK: - Scenario 3: discovery under distractors (plan.md M6.5 scenario 3)

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
/// scenario 3: "wrapped tools where only 2 are relevant." Each instance
/// is fully documented (a real name/description, not a stub) so the
/// completeness contract `ToolAPIRenderer`/`MultiTool.Builder.build()`
/// enforces is satisfied the same way a real third-party tool would be.
struct IntegrationDistractorTool: Tool {
    let name: String
    let description: String

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Echoes the requested id back, labelled with this distractor's name.
    ///
    /// - Parameter arguments: the opaque id to echo.
    /// - Returns: the labelled echo.
    /// - Throws: nothing of its own; the signature is `Tool`'s, and
    ///   `recordCall(to:_:)` only rethrows what its body throws.
    func call(arguments: IntegrationDistractorArguments) async throws -> IntegrationDistractorOutput {
        await log.recordCall(to: name) {
            IntegrationDistractorOutput(value: "distractor:\(name):\(arguments.id)")
        }
    }
}

/// Builds 10 named, distinct distractor tools — combined with the 2 relevant
/// tools (`getWeather`, `getTrip`) the discovery scenario also wraps, the
/// surface totals 12 tools, only 2 of which `searchTools` should select.
///
/// Ten, not the eighteen this list carried through phase 1, by the human
/// ruling of 2026-08-07 recorded on task `tkrdwb8`. The Bisect Protocol
/// measured this scenario as the one carrying essentially the whole
/// baseline-to-HEAD gap (5/5 → 2/5 while the other three scenarios stayed
/// flat), and it is the scenario whose difficulty is set by how much
/// model-visible tool surface competes for attention. Halving the
/// competition is a deliberate change to the scenario, so its pass rate
/// after this change is **not** comparable to any rate recorded before it —
/// see the fresh baseline on that task.
///
/// The ten keep the travel-adjacent names (`bookHotel`, `cancelBooking`,
/// `lookupFlight`, `createCalendarEvent`): those are the distractors that
/// genuinely compete with `getTrip` for a trip-shaped query, so dropping
/// them would have made the scenario easier in a second, hidden way on top
/// of the intended one.
///
/// A function rather than a shared constant, because a distractor records
/// into the run it belongs to: a set built once and reused would carry one
/// scenario's log into the next.
///
/// - Parameter log: the scenario run's call log, shared by all ten.
/// - Returns: the ten distractor tools, in a fixed order.
func integrationDistractorTools(log: ScenarioCallLog) -> [any Tool] {
    [
        ("convertCurrency", "Converts an amount between two currencies."),
        ("bookHotel", "Books a hotel room for given dates."),
        ("cancelBooking", "Cancels an existing booking by id."),
        ("translateText", "Translates text between two languages."),
        ("sendEmail", "Sends an email to a recipient."),
        ("createCalendarEvent", "Creates a calendar event."),
        ("lookupFlight", "Looks up a flight's status by number."),
        ("convertUnits", "Converts a measurement between unit systems."),
        ("summarizeText", "Summarizes a block of text."),
        ("trackPackage", "Tracks a shipment by tracking number."),
    ].map { name, description in
        IntegrationDistractorTool(name: name, description: description, log: log)
    }
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
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level for the same reason as
    /// `IntegrationWeatherTool.path`: the repair scenario names it in what its
    /// answer depends on, since a confirmation is the whole of that answer.
    static let path = "confirmBooking"

    let name = IntegrationBookingTool.path
    let description = "Confirms a trip booking by id."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Confirms the booking `arguments` names, if the caller really asked to.
    ///
    /// The refusal below is recorded as an invocation that did not return:
    /// the model reached this tool, and nothing was confirmed. That is
    /// exactly the difference the repair scenario's side-effect check grades.
    ///
    /// - Parameter arguments: the booking to confirm, and whether to confirm it.
    /// - Returns: the confirmation.
    /// - Throws: `IntegrationBookingError.confirmationRequired` when
    ///   `arguments.confirm` is `false`.
    func call(arguments: IntegrationBookingArguments) async throws -> IntegrationBookingResult {
        try await log.recordCall(to: name) {
            guard arguments.confirm else {
                throw IntegrationBookingError.confirmationRequired
            }
            return IntegrationBookingResult(confirmed: true)
        }
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
    let name = "runDeepScan"
    let description = "Runs a full deep scan of the user's archive and returns that scan's report code. "
        + "The scan takes several seconds to complete."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Runs the scan, slowly, and reports its code.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: the fixture report code.
    /// - Throws: a `CancellationError` if the run is cancelled mid-scan.
    func call(arguments: IntegrationNoArguments) async throws -> IntegrationDeepScanOutput {
        try await log.recordCall(to: name) {
            try await Task.sleep(for: integrationDeepScanDuration)
            return IntegrationDeepScanOutput(reportCode: integrationDeepScanReportCode)
        }
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

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Reports this counter's fixed unit count.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: this counter's unit count.
    /// - Throws: nothing of its own; the signature is `Tool`'s, and
    ///   `recordCall(to:_:)` only rethrows what its body throws.
    func call(arguments: IntegrationNoArguments) async throws -> IntegrationStockCount {
        await log.recordCall(to: name) {
            IntegrationStockCount(units: units)
        }
    }
}

/// How many units the warehouse half of the async fan-out pair reports.
let integrationWarehouseStockUnits = 1904

/// How many units the store-floor half of the async fan-out pair reports.
let integrationStoreStockUnits = 268

/// The async fan-out pair's counters, as the rows both the counters themselves
/// and their `tools.*` paths are built from.
///
/// One table, so `integrationStockTools(log:)` and `integrationStockPaths`
/// cannot come to name different counters.
private let integrationStockCounters: [(path: String, description: String, units: Int)] = [
    (
        "getWarehouseStock",
        "How many units of the product are in the warehouse right now.",
        integrationWarehouseStockUnits
    ),
    (
        "getStoreStock",
        "How many units of the product are on the store floor right now.",
        integrationStoreStockUnits
    ),
]

/// The `tools.*` paths the async fan-out pair mounts under.
///
/// Read off `integrationStockCounters` rather than restated, because the
/// scenario's answer is the two counters' *sum*: it is knowable only when both
/// of them returned, so what it depends on must never drift from what the
/// fixture mounts.
let integrationStockPaths = Set(integrationStockCounters.map(\.path))

/// Builds the async fan-out scenario's pair of independent stock counters.
///
/// A function rather than two shared constants, for two reasons: a counter
/// records into the run it belongs to, so an instance built once and reused
/// would carry one scenario's log into the next; and building both from one
/// table keeps them from drifting into two hand-maintained copies of the same
/// tool.
///
/// - Parameter log: the scenario run's call log, shared by both counters.
/// - Returns: the warehouse counter and the store-floor counter, in that order.
func integrationStockTools(log: ScenarioCallLog) -> [IntegrationStockTool] {
    integrationStockCounters.map { counter in
        IntegrationStockTool(
            name: counter.path,
            description: counter.description,
            units: counter.units,
            log: log
        )
    }
}

// MARK: - What each scenario's answer has to be grounded in

/// The `tools.*` returns each gated scenario's answer depends on — what
/// "grounded" means for the question that scenario actually asks.
///
/// The companion to `IntegrationScenarioAnswers`: that names the substrings a
/// reply is *accepted* for, this names the fixture returns the reply has to
/// rest on. A run is graded grounded when every path the scenario declares here
/// handed a value back (`ScenarioCallLog.returnedPaths`), never when merely
/// *some* fixture call did.
///
/// The weaker question is what let a recorded discovery run pass while holding
/// only the itinerary: it named the warmest city without ever fetching a
/// temperature, and a run that read no reading cannot know which city is
/// warmest (task `0981ar3`). The city names it did have were enough to satisfy
/// "something returned and appears in the answer".
///
/// Every member names paths and never readings, and no path is written out
/// here: each is read from the same declaration the fixture mounting it takes
/// its own name from. A rename therefore cannot leave a scenario depending on
/// a path no fixture mounts.
enum IntegrationScenarioGrounding {
    /// What scenario 1's answer depends on: the reading `getWeather` reports
    /// for `integrationSingleCallCity`. "How warm is it there" is a question
    /// about a temperature, so the city's own name grounds nothing.
    static let singleCall: Set<String> = [IntegrationWeatherTool.path]

    /// What the compose/chain and discovery scenarios' shared answer depends
    /// on: the itinerary that says which cities are candidates, and a
    /// temperature reading that says which of them is warmest. Naming a city
    /// is necessary and not sufficient — it is exactly what the recorded false
    /// pass did.
    static let warmestCity: Set<String> = [IntegrationTripTool.path, IntegrationWeatherTool.path]

    /// What the repair scenario's answer depends on: the confirmation itself.
    /// "Your booking is confirmed" is true only if `confirmBooking` handed a
    /// confirmation back, and that fixture throws rather than confirming when
    /// `confirm` is not `true`, so reaching it proves nothing.
    static let booking: Set<String> = [IntegrationBookingTool.path]

    /// What the async fan-out scenario's answer depends on: both counters,
    /// since only their sum answers the question that scenario asks.
    static let combinedStock = integrationStockPaths
}
