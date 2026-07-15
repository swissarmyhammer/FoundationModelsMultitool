import FoundationModels
import FoundationModelsMetadataRegistry
import os

@testable import FoundationModelsMultitool

// MARK: - `ScriptedAgentSession` — a zero-GPU `AgentSession` fake

/// Thrown by `ScriptedAgentSession.respond(to:)` when it receives more calls
/// than it was scripted with — a test bug (an under-scripted fixture), never
/// a condition the code under test should trigger on a correctly scripted
/// fixture.
struct ScriptedAgentSessionError: Error, Equatable, CustomStringConvertible {
    /// How many scripted responses `respond(to:)` had queued.
    let scriptedResponseCount: Int

    var description: String {
        "ScriptedAgentSession received more calls than its \(scriptedResponseCount) scripted response(s)."
    }
}

/// A scripted `AgentSession` test double: returns its canned `responses` in
/// order, one per call, regardless of the prompt — this test target's
/// zero-GPU stand-in for a real selection-tier session, driven through the
/// registry's `AgentSession` seam (each
/// `RootSessionRespondCalledDirectlySession.fork()` hands one back as the
/// per-call forked session).
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
    /// assert on exactly what the code under test sent (e.g. a selection
    /// call's rendered task prompt).
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
/// goes through a fork() of the prefix-rooted session"). Used by
/// `FindAPIsToolTests`/`ExamplesTests` to drive `FindAPIsTool`'s selection
/// tier without a GPU.
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
