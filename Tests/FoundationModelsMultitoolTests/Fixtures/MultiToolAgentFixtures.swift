import FoundationModels
import FoundationModelsMetadataRegistry
import os

@testable import FoundationModelsMultitool

// MARK: - `ScriptedAgentSession` — M4b's "zero GPU" fake

/// Thrown by `ScriptedAgentSession.respond(to:)` when it receives more calls
/// than it was scripted with — a test bug (an under-scripted fixture), never
/// a condition `MultiToolAgent`'s own loop should trigger on a correctly
/// scripted fixture, since `maxTurns` always bounds how many turns a
/// `respond(to:)` call can take.
struct ScriptedAgentSessionError: Error, Equatable, CustomStringConvertible {
    /// How many scripted responses `respond(to:)` had queued.
    let scriptedResponseCount: Int

    var description: String {
        "ScriptedAgentSession received more calls than its \(scriptedResponseCount) scripted response(s)."
    }
}

/// A scripted `AgentSession` test double: returns its canned `responses` in
/// order, one per call, regardless of the prompt — `MultiToolAgentTests`'
/// zero-GPU stand-in for a real Router session, driving `MultiToolAgent`
/// through the internal `AgentSession` seam that type's own documentation
/// calls for.
///
/// `final class ... Sendable` (not a `struct`) because `respond(to:)` needs
/// to record every prompt it received and advance a call index across
/// `await` boundaries; state lives behind an `OSAllocatedUnfairLock`, the
/// same pattern `DelayedTool`/`RecordingTool` use elsewhere in this test
/// target.
final class ScriptedAgentSession: AgentSession, Sendable {
    /// The mutable state guarded by `stateBox`.
    private struct State {
        /// How many calls `respond(to:)` has handled so far — the index into
        /// `responses` the next call consumes.
        var callCount = 0
        /// Every prompt `respond(to:)` has received, in call order.
        var receivedPrompts: [String] = []
    }

    /// The canned responses returned in order, one per call.
    private let responses: [String]

    /// This session's call state.
    private let stateBox: OSAllocatedUnfairLock<State>

    /// Creates a scripted session that returns `responses` in order, one per
    /// `respond(to:)` call.
    ///
    /// - Parameter responses: the canned responses to return, in call order.
    init(_ responses: [String]) {
        self.responses = responses
        self.stateBox = OSAllocatedUnfairLock(initialState: State())
    }

    /// Every prompt this session received, in call order — lets a test
    /// assert on what `MultiToolAgent` fed back (e.g. a repairable error, or
    /// the discovery-unavailable rejection) as the next turn's prompt.
    var receivedPrompts: [String] { stateBox.withLock { $0.receivedPrompts } }

    /// How many calls this session has handled so far.
    var callCount: Int { stateBox.withLock { $0.callCount } }

    func respond(to prompt: String) async throws -> String {
        let index = stateBox.withLock { state -> Int in
            state.receivedPrompts.append(prompt)
            let index = state.callCount
            state.callCount += 1
            return index
        }
        guard index < responses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: responses.count)
        }
        return responses[index]
    }
}

// MARK: - Canned `Selection` JSON for `CitiesTool` (this file's own fixture
// tool) — the guided-generation shape a real `.selection`-mode
// `MetadataSearcher`'s root session decodes, so a `MultiToolAgentTests`
// scenario can wire a real searcher (via
// `RootSessionRespondCalledDirectlySession`) into `MultiToolAgent`'s
// `findAPIs` dispatch instead of a raw scripted session.

/// One canned, schema-valid `Selection` JSON payload naming `cities` only —
/// matches `CitiesTool`'s `path`, so a `MultiToolAgentTests` scenario can
/// wire a real `.selection`-mode `MetadataSearcher` (via
/// `RootSessionRespondCalledDirectlySession`) into `MultiToolAgent`'s
/// `findAPIs` dispatch instead of a raw scripted session.
let cannedCitiesSelectionJSON = #"{"ids":["cities"]}"#

/// Builds a `.selection`-mode `MetadataSearcher` over `registry.surface
/// .entries`, wired to `root` as its cached root session — the
/// `MetadataSearcher`/`SelectionConfig` analogue of the removed `Librarian(
/// surface:capacityCharacterLimit:makeSession:)` test-facing initializer, so
/// `MultiToolAgentTests`/`GuidedTurnFormatTests` scenarios still exercise the
/// real cached-root/`fork()`-per-call contract — not a reimplementation of
/// it — via `RootSessionRespondCalledDirectlySession`.
///
/// - Parameters:
///   - registry: the catalog to search over.
///   - root: the scripted root session `SelectionConfig.model` hands back on
///     its first (and only) call.
/// - Returns: a `.selection`-mode `MetadataSearcher` over `registry.surface
///   .entries`, guaranteed under budget (`capacityCharacterLimit: .max`) so
///   every call goes through the cached-root + `fork()`-per-call path.
func makeScriptedSelectionSearcher(
    registry: MultiTool.Registry,
    root: any AgentSession
) -> MetadataSearcher<APISurface.Entry> {
    MetadataSearcher(
        items: registry.surface.entries,
        mode: .selection,
        selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
    )
}

// MARK: - `CallCounter` — a thread-safe call counter

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

// MARK: - `RootSessionRespondCalledDirectlySession` — a forking root double

/// Thrown by `RootSessionRespondCalledDirectlySession.respond(to:)` if it is
/// ever called directly — the registry's `SelectionTier` contract is that
/// every `findAPIs`/selection call goes through a `fork()` of the
/// prefix-rooted session, never the root itself
/// (`RoutedSession.fork(workingDirectory:)`'s KV-cache-copy seam only pays
/// off if the root is never asked to generate on its own transcript).
struct RootSessionRespondCalledDirectlyError: Error, Equatable {}

/// A selection-root `AgentSession` double: records how many times `fork()`
/// was called and hands back a fresh, independently-scripted
/// `ScriptedAgentSession` each time — but throws if `respond(to:)` is ever
/// invoked on the root itself, asserting the "always via fork()" contract
/// (M6 acceptance, now the registry's `SelectionTier`: "Each selection call
/// goes through a fork() of the prefix-rooted session").
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

// MARK: - `TripCitiesTool` — a standalone fixture tool

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

// MARK: - A second `TurnFormat` conformer, proving the strategy seam

/// A trivial second `TurnFormat` conformer that ignores the raw turn text
/// entirely and always treats every turn as an immediate `final` answer.
///
/// Exists solely to prove `MultiToolAgentTests`' "turn-strategy seam
/// compiles with a second strategy slot" acceptance criterion: this type is
/// declared entirely outside `TurnFormat.swift`/`MultiToolAgent.swift`, with
/// no change to either, and `MultiToolAgent`'s loop (`respond(to:)`) drives
/// it correctly purely through the `TurnFormat` protocol — exactly the
/// "M4c plugs in without touching loop semantics" property those files'
/// documentation claims.
struct AlwaysFinalTurnFormat: TurnFormat {
    /// Never used: `parseTurn(_:)` here never throws, so
    /// `MultiToolAgent.respond(to:)` never enters its repair path.
    let maxRepairTurns = 0

    /// A fixed note; this fixture ignores `supportsFindAPIs`/`supportsDirectCall`
    /// since it never distinguishes actions in the first place.
    func formatInstructions(supportsFindAPIs: Bool, supportsDirectCall: Bool) -> String {
        "Respond with anything; every turn is treated as the final answer."
    }

    /// Always succeeds, treating `raw` verbatim as the final answer.
    func parseTurn(_ raw: String) throws -> AgentStep {
        .final(text: raw)
    }

    /// Never called, since `parseTurn(_:)` never throws.
    func repairInstruction(for error: Error) -> String {
        "unreachable: parseTurn(_:) never throws"
    }
}
