import FoundationModelsRouter

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

    /// The ambient ``ToolContext`` the first *entered* invocation ran under, or
    /// `nil` when no fixture tool has been entered yet.
    ///
    /// Kept so a scenario can read the session's **run plane** after its turn
    /// is over. A `ToolContext` is the only route to that plane (Router task
    /// `^k0mecjp`), it exists only inside a tool call, and every context bound
    /// during one session names that session's own plane — so the first one a
    /// fixture tool saw is a usable handle to it afterwards.
    ///
    /// This is what makes "no run survives the call" assertable at all. It is
    /// an observation of the product's own wiring, not a back door: the
    /// capability it reads is the same public one `status()` and `wait` use.
    ///
    /// Recorded when a call is *entered*, never when it completes, so the plane
    /// is readable **while** a fixture tool is still working. The parked-run
    /// drain scenario reads it at exactly that moment — the instant the model's
    /// answer lands, with its slow fixture still held open — and recording the
    /// handle on completion would have made that read report an empty plane and
    /// grade a real parked run as none.
    private(set) var observedContext: ToolContext?

    /// The runs still parked on the session this log's tools ran under.
    ///
    /// - Returns: every parked run, or an empty array when no fixture tool was
    ///   ever entered — in which case a scenario has a bigger problem than the
    ///   run plane, and its groundedness assertion will say so first.
    func parkedRuns() async -> [ParkedRun] {
        await observedContext?.parkedRuns() ?? []
    }

    /// How one run of this log's session ended, read back off the run plane's
    /// retained terminal event.
    ///
    /// Settled runs are retained by token (`SessionMailbox.settledTerminalEvents`),
    /// so a run collected during a turn is still answerable for after that turn
    /// — which is how a scenario tells a run the drain *settled* from a run
    /// something *swept*: the terminal event carries the outcome its own work
    /// reported.
    ///
    /// - Parameter completionToken: the run's completion token.
    /// - Returns: `.settled` with the retained terminal event for a run that has
    ///   ended, `.deadlineElapsed` for one still running, or `.unknownToken`
    ///   when this log never saw a context to ask through.
    func settlement(of completionToken: String) async -> WaitOutcome {
        guard let observedContext else { return .unknownToken }
        // Zero seconds: this asks what the plane already knows, and never waits.
        // A still-running run answers `.deadlineElapsed` rather than holding the
        // caller, which is the honest answer to "has it ended yet".
        return await observedContext.wait(completionToken: completionToken, seconds: 0)
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
        // Read here, inside the call, because that is the only place an ambient
        // context exists — by the time a scenario asserts, every binding is
        // gone and the handle recorded here is what is left of the session's
        // run plane.
        //
        // Handed over before `body` runs, not after: see `observedContext` for
        // the scenario that reads the plane while a fixture call is still open.
        await observe(ToolContext.current)
        do {
            let value = try await body()
            await append(ScenarioCall(path: path, outcome: .returned))
            return value
        } catch {
            await append(ScenarioCall(path: path, outcome: .threw))
            throw error
        }
    }

    /// Keeps the ambient context one entering invocation ran under, if this log
    /// has not already kept one.
    ///
    /// Only the first is kept: every later one names the same session's run
    /// plane, and the first is the one certain to exist by the time any scenario
    /// reads it.
    ///
    /// - Parameter ambient: the context that invocation ran under, if any.
    private func observe(_ ambient: ToolContext?) {
        guard observedContext == nil else { return }
        observedContext = ambient
    }

    /// Appends one recorded invocation.
    ///
    /// - Parameter call: the invocation to record.
    private func append(_ call: ScenarioCall) {
        calls.append(call)
    }
}
