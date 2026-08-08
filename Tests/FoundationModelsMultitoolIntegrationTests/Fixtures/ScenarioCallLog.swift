/// One fixture tool invocation, as the tool itself recorded it while running.
///
/// The unit `ScenarioCallLog` stores. The outcome is carried alongside the
/// path because a gated scenario asks two different questions of the same
/// invocation — "did the model reach a real tool at all" and "did a tool hand
/// data back" — and a call that entered and then threw answers them
/// differently.
struct ScenarioCall: Equatable, Sendable {
    /// How one invocation ended.
    enum Outcome: Equatable, Sendable {
        /// The tool's body ran to completion and handed its result back to the
        /// awaiting snippet.
        case returned

        /// The tool's body threw, so the awaiting snippet saw a rejection and
        /// no value came back.
        case threw
    }

    /// The `tools.*` path that ran — the invoked tool's own `name`.
    let path: String

    /// How this invocation ended.
    let outcome: Outcome
}

/// The record of which fixture tools a scenario's snippets genuinely ran.
///
/// The gated scenarios used to answer "did this really happen?" by scanning
/// each `runCode` snippet's *source* for `tools.<path>` call sites — a report
/// of what the model typed, which is a different thing from what executed. A
/// recorded compose run (task `0981ar3`) scored `grounded=pass` on two call
/// sites naming functions no mounted fixture defined: both calls threw,
/// nothing ran, and the temperature in the reply came from nowhere. The
/// fixture tools are this suite's own code, so the honest answer is for each
/// of them to say so as it runs, and that is what this records.
///
/// An `actor` because every fixture tool's `call(arguments:)` is `async
/// throws` and a snippet is free to drive several at once — the async fan-out
/// scenario's natural snippet is a `Promise.all` over two tools — so
/// invocations genuinely race.
///
/// One log belongs to one scenario run. `runNativeIntegrationScenario` mints a
/// fresh one per run and builds that run's tools around it, so no scenario can
/// read back what another scenario did.
actor ScenarioCallLog {
    /// Every invocation recorded so far, in the order the invocations finished.
    ///
    /// Ordered rather than a set, so a later reader can ask about call order
    /// as well as call membership.
    private(set) var calls: [ScenarioCall] = []

    /// The distinct `tools.*` paths a fixture tool actually entered, however each call then ended.
    var invokedPaths: Set<String> {
        Set(calls.map(\.path))
    }

    /// The distinct `tools.*` paths whose call handed a value back rather than throwing.
    var returnedPaths: Set<String> {
        Set(calls.lazy.filter { $0.outcome == .returned }.map(\.path))
    }

    /// Runs one fixture tool's body and records the invocation it makes.
    ///
    /// Every fixture tool routes its `call(arguments:)` through here, so all
    /// six record the same way and a tool that throws is still recorded — as
    /// entered-but-not-returned. That matters: `IntegrationWeatherTool`
    /// refuses a city it cannot resolve and `IntegrationBookingTool` refuses
    /// an unconfirmed booking, and both refusals are invocations a scenario
    /// needs to see rather than calls that never happened.
    ///
    /// A `do`/`catch` that re-throws rather than a `defer`, because a `defer`
    /// body may not suspend and appending to this actor is an `await`.
    ///
    /// - Parameters:
    ///   - path: the `tools.*` path being invoked — the calling tool's `name`.
    ///   - body: the tool's own work.
    /// - Returns: whatever `body` returned.
    /// - Throws: whatever `body` threw, unchanged.
    nonisolated func recordCall<Value>(
        to path: String,
        _ body: () async throws -> Value
    ) async rethrows -> Value {
        do {
            let value = try await body()
            await append(ScenarioCall(path: path, outcome: .returned))
            return value
        } catch {
            await append(ScenarioCall(path: path, outcome: .threw))
            throw error
        }
    }

    /// Appends one recorded invocation.
    ///
    /// - Parameter call: the invocation to record.
    private func append(_ call: ScenarioCall) {
        calls.append(call)
    }
}
