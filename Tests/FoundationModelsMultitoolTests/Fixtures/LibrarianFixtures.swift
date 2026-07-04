import FoundationModels
import FoundationModelsMetadataRegistry
import os

@testable import FoundationModelsMultitool

// MARK: - M6 `Librarian`/`FindAPITool` fixtures (plan.md § "Discovery: a
// prefix-cached librarian" + M6)
//
// `LibrarianTests` never touches a real Router model — the librarian's root
// session is always supplied through the internal `AgentSession` seam, the
// same zero-GPU pattern `MultiToolAgentTests` established (M4b). Reuses
// `WeatherTool` (`ToolAPIRendererFixtures.swift`) for one fixture surface
// entry; `TripCitiesTool` below adds a second, matching plan.md's own worked
// `tripCities()` example so the fixture surface reads like the plan's
// concrete "assembled prompt" illustration.

/// The `Output` of `TripCitiesTool` — plan.md's own worked
/// `tripCities(): string[]` example.
@Generable
struct TripCitiesOutput {
    var cities: [String]
}

/// A standalone, no-argument tool returning a fixed trip itinerary — reuses
/// `NoArguments` (`MultiToolExecutionFixtures.swift`), the established
/// zero-meaningful-argument fixture shape this test target already uses for
/// `CitiesTool`.
struct TripCitiesTool: Tool {
    let name = "tripCities"
    let description = "The cities on the user's current trip, in itinerary order."

    func call(arguments: NoArguments) async throws -> TripCitiesOutput {
        TripCitiesOutput(cities: ["ATX", "SFO"])
    }
}

// MARK: - The `AgentSession` seam: a forking root double + a fork-tracking wrapper

/// Thrown by `RootSessionRespondCalledDirectlySession.respond(to:)` if it is ever
/// called directly — plan.md's librarian contract is that every `findAPIs`
/// call goes through a `fork()` of the prefix-rooted session, never the root
/// itself (`RoutedSession.fork(workingDirectory:)`'s KV-cache-copy seam only
/// pays off if the root is never asked to generate on its own transcript).
struct RootSessionRespondCalledDirectlyError: Error, Equatable {}

/// A librarian-root `AgentSession` double: records how many times
/// `fork()` was called and hands back a fresh, independently-scripted
/// `ScriptedAgentSession` (M4b's existing fixture) each time — but throws if
/// `respond(to:)` is ever invoked on the root itself, asserting the
/// "always via fork()" contract (M6 acceptance: "Each findAPIs call goes
/// through a fork() of the prefix-rooted session").
///
/// `final class ... Sendable` for the same reason as `ScriptedAgentSession`:
/// `fork()` needs to record a call count visible after the `async` call
/// returns, backed by an `OSAllocatedUnfairLock`.
final class RootSessionRespondCalledDirectlySession: AgentSession, Sendable {
    /// One scripted response per `fork()` call, in fork order — the raw
    /// guided-generation JSON text the resulting fork's `respond(to:)`
    /// returns.
    private let forkResponses: [String]

    /// How many `fork()` calls this root has handled so far.
    private let forkCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a root double that hands back one freshly-scripted fork per
    /// `fork()` call, in order.
    ///
    /// - Parameter forkResponses: one canned raw response per expected
    ///   `fork()` call, in call order.
    init(forkResponses: [String]) {
        self.forkResponses = forkResponses
    }

    /// How many `fork()` calls this root has handled so far.
    var forkCount: Int { forkCountBox.withLock { $0 } }

    func respond(to prompt: String) async throws -> String {
        throw RootSessionRespondCalledDirectlyError()
    }

    func fork() async throws -> any AgentSession {
        let index = forkCountBox.withLock { count -> Int in
            let index = count
            count += 1
            return index
        }
        guard index < forkResponses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: forkResponses.count)
        }
        return ScriptedAgentSession([forkResponses[index]])
    }
}

/// Records every `instructions` string a `Librarian`'s session factory
/// closure was called with, returning one freshly-scripted
/// `ScriptedAgentSession` (canned with `responses`) per call — lets a test
/// assert both on *how many times* a session was created (proving the root
/// session is cached, not rebuilt per `findAPIs` call) and on *what prefix
/// text* was actually seeded (e.g. that a lexically pre-filtered surface
/// excludes an irrelevant block).
final class RecordingSessionFactory: Sendable {
    /// The canned responses every created session is scripted with.
    private let responses: [String]

    /// Every `instructions` string `makeSession(instructions:)` has been
    /// called with, in call order.
    private let receivedInstructionsBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Creates a factory whose every vended session is scripted with
    /// `responses`.
    ///
    /// - Parameter responses: the canned responses every created session
    ///   returns, in call order.
    init(responses: [String]) {
        self.responses = responses
    }

    /// Every `instructions` string this factory has been called with, in
    /// call order.
    var receivedInstructions: [String] { receivedInstructionsBox.withLock { $0 } }

    /// Creates and records a new scripted session — `Librarian`'s
    /// `makeSession` factory parameter.
    ///
    /// - Parameter instructions: the instructions text to record.
    /// - Returns: a freshly-scripted `ScriptedAgentSession`.
    func makeSession(instructions: String) -> any AgentSession {
        receivedInstructionsBox.withLock { $0.append(instructions) }
        return ScriptedAgentSession(responses)
    }
}

/// A thread-safe call counter — used to assert a closure ran an exact number
/// of times without needing a bespoke lock-boxed fixture per test.
final class CallCounter: Sendable {
    /// This counter's current count.
    private let countBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a counter starting at `0`.
    init() {}

    /// Increments the count and returns its new value.
    ///
    /// - Returns: the count after incrementing.
    @discardableResult
    func increment() -> Int {
        countBox.withLock { count -> Int in
            count += 1
            return count
        }
    }

    /// This counter's current count.
    var count: Int { countBox.withLock { $0 } }
}

// MARK: - Canned `FoundAPIs` JSON — the guided-generation shape a real
// `RoutedLLM.respond(to:generating: FoundAPIs.self)` call decodes.

/// One canned, schema-valid `FoundAPIs` JSON payload naming `tripCities`
/// only — matches `TripCitiesTool`'s rendered descriptor fields exactly, so
/// a test can assert the decoded `FoundAPI.signature`/`doc`/`example` are
/// spliced through verbatim.
let cannedTripCitiesFoundAPIsJSON = """
    {"functions":[{"name":"tripCities","signature":"tools.tripCities(): string[]",\
    "doc":"The cities on the user's current trip, in itinerary order.",\
    "example":"const cs = tools.tripCities();"}]}
    """

/// A second canned payload naming `weather` — used where a test needs a
/// distinct relevant block (e.g. the capacity-pre-filter scenario, where
/// `weather` is the block that must survive a lexical filter for a
/// weather-flavored task).
let cannedWeatherFoundAPIsJSON = """
    {"functions":[{"name":"weather","signature":"tools.weather(args: { city: string }): { tempC: number }",\
    "doc":"Current weather for a city.","example":"const c = tools.weather({ city: \\"ATX\\" }).tempC;"}]}
    """
