import Foundation
import FoundationModels
import FoundationModelsRouter

// MARK: - The weather tool of the discovery scenario (plan.md M6.5 scenario 1)

/// `IntegrationWeatherTool`'s arguments.
@Generable
public struct IntegrationWeatherArguments {
    /// The city to read, as an IATA code or as a spelled-out name.
    @Guide(description: "IATA city code or city name.")
    public var city: String

    /// Creates the arguments for one `getWeather` call.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only, and both test targets call this fixture
    /// directly as well as through a model.
    ///
    /// - Parameter city: the IATA code or spelled-out name to resolve.
    public init(city: String) {
        self.city = city
    }
}

/// `IntegrationWeatherTool`'s output.
@Generable(description: "current conditions.")
public struct IntegrationWeatherResult {
    /// The city's temperature, in °C.
    public var tempC: Double

    /// A short description of the conditions.
    public var summary: String
}

/// One trip city's fixture weather reading.
public struct IntegrationCityWeather: Sendable {
    /// The IATA code `IntegrationTripTool` reports this city by.
    public let code: String

    /// The city's spelled-out name, which models routinely expand codes to.
    public let name: String

    /// The city's temperature, in °C.
    public let tempC: Double
}

/// Austin's fixture temperature, in °C. `integrationCityWeather` gives the
/// reason the three readings are different from each other.
let integrationAustinTempC: Double = 31

/// San Francisco's fixture temperature, in °C. It is the highest of the three
/// readings, thus San Francisco is the warmest trip city.
let integrationSanFranciscoTempC: Double = 34

/// New York's fixture temperature, in °C. It is the lowest of the three
/// readings.
let integrationNewYorkTempC: Double = 22

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
/// evidence the snippet really read the readings.
public let integrationCityWeather: [IntegrationCityWeather] = [
    IntegrationCityWeather(code: "ATX", name: "Austin", tempC: integrationAustinTempC),
    IntegrationCityWeather(code: "SFO", name: "San Francisco", tempC: integrationSanFranciscoTempC),
    IntegrationCityWeather(code: "NYC", name: "New York", tempC: integrationNewYorkTempC),
]

/// How many readings `integrationCityWeather` must hold before "which city is
/// warmest?" is a question. With only one reading there is nothing to compare.
let integrationWarmestCityMinimumReadings = 2

/// The single warmest trip city — the one correct answer to the discovery
/// scenario's question.
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
public let integrationWarmestCity: IntegrationCityWeather = {
    let byDescendingTemperature = integrationCityWeather.sorted { $0.tempC > $1.tempC }
    precondition(
        byDescendingTemperature.count >= integrationWarmestCityMinimumReadings,
        "integrationCityWeather needs at least two readings for \"which is warmest?\" to be a question"
    )
    precondition(
        byDescendingTemperature[0].tempC > byDescendingTemperature[1].tempC,
        """
        integrationCityWeather ties for warmest at \(byDescendingTemperature[0].tempC) °C \
        (\(byDescendingTemperature[0].code) and \(byDescendingTemperature[1].code)); the discovery \
        scenario grades on there being exactly one warmest trip city
        """
    )
    return byDescendingTemperature[0]
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

/// The substrings the discovery scenario accepts as its answer.
///
/// Both sets are derived from `integrationCityWeather`, so an assertion built
/// on them cannot drift from the readings it grades.
public enum IntegrationScenarioAnswers {
    /// The only valid answers to the discovery scenario's question, "which
    /// trip city is warmest": the single warmest fixture city, by IATA code
    /// and by the spelled-out name models routinely expand codes to. Any other
    /// city is wrong.
    public static let warmestCity = [integrationWarmestCity.code, integrationWarmestCity.name]

    /// The only valid answers to the second half of the discovery scenario's
    /// question, "how warm is it there": the warmest city's own reading.
    ///
    /// This is the check the single-call weather scenario made, which card
    /// `^3vtvrzg` merged into the discovery scenario: a reply that states the
    /// reading proves a `getWeather` return reached the answer. It is a
    /// number that no hallucinated forecast has given in the recorded runs
    /// (they said 72°F, 25°C, 22°C), and the grounding check requires the
    /// `getWeather` call that returned it.
    public static let warmestCityReading = [integrationTemperatureAnswer(integrationWarmestCity.tempC)]
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
public enum IntegrationWeatherError: Error, Equatable, CustomStringConvertible {
    /// No fixture reading matches the requested city.
    case unknownCity(String)

    /// The requested city matches more than one fixture reading, named here.
    case ambiguousCity(String, matches: [String])

    public var description: String {
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

/// The weather tool the discovery scenario asserts the model finds and calls,
/// rather than hallucinating an answer — plan.md M6.5 scenario 1, which card
/// `^3vtvrzg` merged into the discovery scenario.
public struct IntegrationWeatherTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level so a scenario can name the path its answer
    /// depends on — see `IntegrationScenarioGrounding` — without spelling the
    /// string a second time somewhere a rename would not reach.
    public static let path = "getWeather"

    public let name = IntegrationWeatherTool.path
    public let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Creates the weather fixture, recording into `log`.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only, and `IntegrationWeatherTool` is mounted from
    /// both test targets.
    ///
    /// - Parameter log: the scenario run's call log this tool records into.
    public init(log: ScenarioCallLog) {
        self.log = log
    }

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
    public func call(arguments: IntegrationWeatherArguments) async throws -> IntegrationWeatherResult {
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

// MARK: - The trip tool of the discovery scenario: `getTrip` -> `getWeather` -> warmest (plan.md M6.5 scenario 2)

/// Arguments for a tool that takes nothing meaningful — every `Tool
/// .Arguments` must be an `object` schema, so an unused optional field
/// stands in for "no arguments", mirroring the main test target's own
/// `NoArguments` fixture (a distinct module, so redeclared here).
@Generable
public struct IntegrationNoArguments {
    /// The field that stands in for "no arguments". It carries nothing, and a
    /// caller writing these arguments by hand passes `nil`.
    @Guide(description: "unused.")
    public var unused: String?

    /// Creates the arguments for a tool that takes nothing.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameter unused: the field that stands in for "no arguments"; a
    ///   caller writing these arguments by hand passes `nil`.
    public init(unused: String?) {
        self.unused = unused
    }
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
public struct IntegrationTripOutput {
    /// The trip's booking reference.
    public var confirmationCode: String

    /// The traveler's name.
    public var traveler: String

    /// The first day of the trip, as `YYYY-MM-DD`.
    public var startDate: String

    /// The last day of the trip, as `YYYY-MM-DD`.
    public var endDate: String

    /// The trip's cities, by IATA code, in itinerary order.
    public var cities: [String]
}

/// The first half of the compose walk the discovery scenario asks for.
public struct IntegrationTripTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level for the same reason as
    /// `IntegrationWeatherTool.path`: the discovery scenario names it in what
    /// its answer depends on.
    public static let path = "getTrip"

    public let name = IntegrationTripTool.path
    public let description = "The user's current trip: its cities in itinerary order, plus its dates, "
        + "its traveler and its booking confirmation code."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Creates the trip fixture, recording into `log`.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only, and `IntegrationTripTool` is mounted from
    /// both test targets.
    ///
    /// - Parameter log: the scenario run's call log this tool records into.
    public init(log: ScenarioCallLog) {
        self.log = log
    }

    /// Reports the fixture itinerary.
    ///
    /// - Parameter arguments: unused — this tool takes nothing.
    /// - Returns: the fixture trip.
    /// - Throws: nothing of its own; the signature is `Tool`'s, and
    ///   `recordCall(to:_:)` only rethrows what its body throws.
    public func call(arguments: IntegrationNoArguments) async throws -> IntegrationTripOutput {
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
public func integrationDistractorTools(log: ScenarioCallLog) -> [any Tool] {
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
public struct IntegrationBookingArguments {
    /// The booking to confirm.
    @Guide(description: "the booking id to confirm.")
    public var id: Int

    /// Whether the caller really asks for the booking to be confirmed. The
    /// tool throws on anything but `true`.
    @Guide(description: "must be set to true to actually confirm the booking.")
    public var confirm: Bool
}

/// `IntegrationBookingTool`'s output.
@Generable
public struct IntegrationBookingResult {
    /// Whether the booking is now confirmed. Always `true`: the tool throws
    /// rather than report a booking it did not confirm.
    public var confirmed: Bool
}

/// Thrown by `IntegrationBookingTool.call` when a well-formed call
/// nonetheless passes `confirm: false` — `ToolInvoker`/`ResultRenderer` turn
/// this into the repairable error text fed back to the model, exercising the
/// same repair mechanics as an omitted `confirm` tripping decode validation.
public enum IntegrationBookingError: Error, CustomStringConvertible {
    case confirmationRequired
    public var description: String { "booking requires confirm: true" }
}

/// A deliberately trip-prone tool — plan.md M6.5 scenario 4: "a tool the
/// model tends to mis-call." Its description alone ("confirms a booking")
/// doesn't spell out that `confirm` must explicitly be `true`, so a model's
/// first attempt commonly omits `confirm` (tripping argument decoding) or
/// passes `false` (tripping this `call`'s own guard) — either way, the
/// resulting repairable error is exactly what the repair-loop scenario needs
/// to recover from.
public struct IntegrationBookingTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level for the same reason as
    /// `IntegrationWeatherTool.path`: the repair scenario names it in what its
    /// answer depends on, since a confirmation is the whole of that answer.
    public static let path = "confirmBooking"

    public let name = IntegrationBookingTool.path
    public let description = "Confirms a trip booking by id."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Creates the booking fixture, recording into `log`.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only, and `IntegrationBookingTool` is mounted from
    /// both test targets.
    ///
    /// - Parameter log: the scenario run's call log this tool records into.
    public init(log: ScenarioCallLog) {
        self.log = log
    }

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
    public func call(arguments: IntegrationBookingArguments) async throws -> IntegrationBookingResult {
        try await log.recordCall(to: name) {
            guard arguments.confirm else {
                throw IntegrationBookingError.confirmationRequired
            }
            return IntegrationBookingResult(confirmed: true)
        }
    }
}

// MARK: - Scenario 8: an unguided generation nested inside a tool call

// The tool itself stands in the gated package, at
// `IntegrationTests/.../Fixtures/IntegrationNestedGenerationTool.swift`: its
// body opens a nested generation on a resolved slot, so it drives a model.
// What stays here is what the grading rule and its ungated coverage read.

/// The `tools.*` path the nested-generation probe's one tool mounts under.
///
/// A constant of its own, rather than a `static let` on that tool, because the
/// tool and the rule that grades it now stand in different modules.
/// `nestedGenerationChecks(for:)` reads plain values and stands here; the tool
/// generates and stands in the gated package. Both name this one string, so
/// neither can drift from the other.
public let integrationNestedGenerationPath = "checkModelReadiness"

/// The readiness token `IntegrationNestedGenerationTool` reports once its
/// nested call has ended.
///
/// A string no model would volunteer: an answer carrying it rests on this
/// fixture's own return rather than on anything the model could have supplied
/// itself. The probe does not grade the reply. It grades how the nested call
/// ended, which `NestedGenerationOutcome` records.
public let integrationNestedGenerationToken = "READY-7Q4X"

// MARK: - Scenario 9: the delayed echo of the mail collection canary (task `^nhxj8hx`)

/// The count of seconds in `integrationDelayedEchoDelay`.
///
/// This declaration names the number directly, so no call site passes a raw
/// literal — `integrationDelayedEchoDelay` turns it into a `Duration`. The
/// reasons for the value stand on that constant.
public let integrationDelayedEchoDelaySeconds = 7

/// `IntegrationDelayedEchoTool`'s arguments.
@Generable
public struct IntegrationDelayedEchoArguments {
    /// The value the echo must hand back unchanged.
    @Guide(description: "the value to echo back.")
    public var value: String

    /// Creates the arguments for one `echoAfterDelay` call.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameter value: the value the echo must hand back unchanged.
    public init(value: String) {
        self.value = value
    }
}

/// `IntegrationDelayedEchoTool`'s output.
@Generable(description: "the echoed value.")
public struct IntegrationDelayedEchoOutput {
    /// The value the call was given, unchanged.
    public var value: String
}

/// How long `IntegrationDelayedEchoTool` holds its value before it settles.
///
/// **The delay must be longer than `runCode`'s inline settle grace**
/// (`MultiToolConfiguration.defaultInlineSettleGrace`, five seconds). A run
/// that settles inside the grace gives its result inline, and the deferred
/// path goes untested (task `^nhxj8hx`). This delay keeps the run in the
/// `running` state past the instant its `runCode` call answers, so the result
/// must come back later, as mail.
///
/// Seven seconds: the grace and two seconds more. The delay was four seconds,
/// and a live run on 2026-09-26 (task `^r77er9z`) showed the fault: the echo
/// settled inside the grace, the model got the value inline, and no mail came.
/// It was then ten seconds, two times the grace. Card `^3vtvrzg` made it
/// shorter: the echo starts its delay after the `runCode` call starts its
/// grace, so any delay longer than the grace settles after the pending
/// envelope, and each second past that margin only lengthens the run.
/// `ScenarioFixtureTests` makes sure that this delay stays longer than the
/// grace: when the grace changes, that test fails until this value changes
/// too. It stays far under `MultiToolConfiguration.executionTimeLimit`, the
/// sandbox work clock, so a snippet that awaits the echo in line still
/// completes.
public let integrationDelayedEchoDelay: Duration = .seconds(integrationDelayedEchoDelaySeconds)

/// How many characters `integrationDelayedEchoNonce()` returns.
///
/// Twelve hex characters carry 48 random bits: enough that no two runs
/// collide and no model states the value from its priors, and short enough
/// that a reply quotes it verbatim rather than reformatting it.
public let integrationDelayedEchoNonceLength = 12

/// Makes one fresh nonce for a delayed-echo run.
///
/// Fresh per run, never a fixture constant, on the card's rule
/// (task `^nhxj8hx`): a constant would sit in this repo where a model could
/// have seen it, and two runs could satisfy each other's answers. A value
/// minted at run time can reach the reply only through this run.
///
/// - Returns: `integrationDelayedEchoNonceLength` hex characters drawn from a
///   fresh UUID.
public func integrationDelayedEchoNonce() -> String {
    String(UUID().uuidString.filter(\.isHexDigit).prefix(integrationDelayedEchoNonceLength))
}

/// The tool the mail collection canary drives: it takes a value, hands the
/// caller a handle at once, and settles with that value
/// `integrationDelayedEchoDelay` later.
///
/// The description says the result settles in the background, and stops
/// there. It does not tell the model what to do while it runs: whether the
/// model ends its answer and reads the result from the mail is exactly what
/// the canary measures, so the pending envelope on the handle carries that
/// instruction, and it must stay the only source of it.
public struct IntegrationDelayedEchoTool: Tool {
    /// The `tools.*` path this fixture mounts under.
    ///
    /// Declared at the type level for the same reason as
    /// `IntegrationWeatherTool.path`: the canary names it in its prompt and
    /// in what its answer depends on.
    public static let path = "echoAfterDelay"

    public let name = IntegrationDelayedEchoTool.path
    public let description = "Returns the exact value you pass it. "
        + "The result settles in the background a few seconds after the call."

    /// The scenario run's call log every invocation of this tool records itself in.
    let log: ScenarioCallLog

    /// Creates the delayed-echo fixture, recording into `log`.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only, and `IntegrationDelayedEchoTool` is mounted from
    /// both test targets.
    ///
    /// - Parameter log: the scenario run's call log this tool records into.
    public init(log: ScenarioCallLog) {
        self.log = log
    }

    /// Waits `integrationDelayedEchoDelay`, then reports the value back.
    ///
    /// - Parameter arguments: the value to echo.
    /// - Returns: that exact value.
    /// - Throws: a `CancellationError` if the run is cancelled mid-delay.
    public func call(arguments: IntegrationDelayedEchoArguments) async throws -> IntegrationDelayedEchoOutput {
        try await log.recordCall(to: name) {
            try await Task.sleep(for: integrationDelayedEchoDelay)
            return IntegrationDelayedEchoOutput(value: arguments.value)
        }
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
public enum IntegrationScenarioGrounding {
    /// What the discovery scenario's answer depends on: the itinerary that
    /// says which cities are candidates, and a temperature reading that says
    /// which of them is warmest and how warm it is. Naming a city is necessary
    /// and not sufficient — it is exactly what the recorded false pass did.
    public static let warmestCity: Set<String> = [IntegrationTripTool.path, IntegrationWeatherTool.path]

    /// What the repair scenario's answer depends on: the confirmation itself.
    /// "Your booking is confirmed" is true only if `confirmBooking` handed a
    /// confirmation back, and that fixture throws rather than confirming when
    /// `confirm` is not `true`, so reaching it proves nothing.
    public static let booking: Set<String> = [IntegrationBookingTool.path]

    /// What the mail collection canary's answer depends on: the echo's own
    /// return. The nonce is in the prompt — the model has to pass it — so the
    /// reply alone cannot prove the round trip. This path proves the echo
    /// really handed the value back, and the mail collection check proves the
    /// run that carried it came back to the model as mail.
    public static let delayedEcho: Set<String> = [IntegrationDelayedEchoTool.path]
}
