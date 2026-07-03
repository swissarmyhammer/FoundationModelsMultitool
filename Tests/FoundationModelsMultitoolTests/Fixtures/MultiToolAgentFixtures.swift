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

// MARK: - Canned `FoundAPIs` JSON for `CitiesTool` (this file's own fixture
// tool) — the guided-generation shape a real `Librarian`'s root session
// decodes, mirroring `LibrarianFixtures.swift`'s `cannedTripCitiesFoundAPIsJSON`
// for `MultiToolAgentTests`' own `CitiesTool`-based scenarios.

/// One canned, schema-valid `FoundAPIs` JSON payload naming `cities` only —
/// matches `CitiesTool`'s shape, so a `MultiToolAgentTests` scenario can wire
/// a real `Librarian` (via `RootSessionRespondCalledDirectlySession`) into
/// `MultiToolAgent`'s `findAPIs` dispatch instead of a raw scripted session.
let cannedCitiesFoundAPIsJSON = """
    {"functions":[{"name":"cities","signature":"tools.cities(): { cities: string[] }",\
    "doc":"The cities on the trip.","example":"tools.cities().cities;"}]}
    """

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
