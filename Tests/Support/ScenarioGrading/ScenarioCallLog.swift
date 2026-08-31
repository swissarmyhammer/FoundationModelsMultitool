import FoundationModelsRouter

/// One fixture tool invocation, as the tool itself recorded it while running.
///
/// The unit `ScenarioCallLog` stores. The outcome is carried alongside the
/// path because a gated scenario asks two different questions of the same
/// invocation — "did the model reach a real tool at all" and "did a tool hand
/// data back" — and a call that entered and then threw answers them
/// differently.
public struct ScenarioCall: Equatable, Sendable {
    /// How one invocation ended.
    public enum Outcome: Equatable, Sendable {
        /// The tool's body ran to completion and handed its result back to the
        /// awaiting snippet.
        case returned

        /// The tool's body threw, so the awaiting snippet saw a rejection and
        /// no value came back.
        case threw
    }

    /// The `tools.*` path that ran — the invoked tool's own `name`.
    public let path: String

    /// How this invocation ended.
    public let outcome: Outcome

    /// Records one invocation.
    ///
    /// Explicit because a `public` struct's synthesized memberwise initializer
    /// is `internal` only.
    ///
    /// - Parameters:
    ///   - path: the `tools.*` path that ran.
    ///   - outcome: how the invocation ended.
    public init(path: String, outcome: Outcome) {
        self.path = path
        self.outcome = outcome
    }
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
public actor ScenarioCallLog {
    /// Creates a log that has recorded nothing.
    ///
    /// Explicit because a `public` actor's synthesized initializer is
    /// `internal` only.
    public init() {}

    /// Every invocation recorded so far, in the order the invocations finished.
    ///
    /// Ordered rather than a set, so a later reader can ask about call order
    /// as well as call membership.
    public private(set) var calls: [ScenarioCall] = []

    /// The distinct `tools.*` paths a fixture tool entered *and finished*,
    /// however each call then ended.
    ///
    /// Read off ``calls``, which is appended to when a call completes — so a
    /// call still running, or one that will never finish, is in neither this
    /// set nor ``returnedPaths``. Every scenario that reads this grades a run
    /// after its turn is over, where the distinction cannot arise; a scenario
    /// that has to tell "never called" from "called and never came back" reads
    /// ``enteredPaths`` instead.
    public var invokedPaths: Set<String> {
        Set(calls.map(\.path))
    }

    /// The distinct `tools.*` paths a fixture tool entered, recorded on the way
    /// in and never removed.
    ///
    /// The companion to ``invokedPaths``, and the difference between them is
    /// exactly one case: a call that entered and did not come back. That case
    /// is not hypothetical. The gated run of `runNestedGenerationProbe` on
    /// 2026-08-16 sat 165 seconds inside one tool call whose nested `respond`
    /// was parked on Router's generation gate, and `invokedPaths` reported the
    /// empty set for it — the same reading a model that never called the tool
    /// produces, and the opposite conclusion.
    public private(set) var enteredPaths: Set<String> = []

    /// The distinct `tools.*` paths whose call handed a value back rather than throwing.
    public var returnedPaths: Set<String> {
        Set(calls.lazy.filter { $0.outcome == .returned }.map(\.path))
    }

    /// The ambient ``ToolContext`` the first *entered* invocation ran under, or
    /// `nil` when no fixture tool has been entered yet.
    ///
    /// Kept so a scenario can read the session's **background runs** after its
    /// turn is over. A `ToolContext` is the only route to them (Router task
    /// `^k0mecjp`), it exists only inside a tool call, and every context bound
    /// during one session names that session's own runs — so the first one a
    /// fixture tool saw is a usable handle to them afterwards.
    ///
    /// This is what makes "no run survives the call" assertable at all. It is
    /// an observation of the product's own wiring, not a back door: the
    /// capability it reads is the same public one `status()` and `wait` use.
    ///
    /// Recorded when a call is *entered*, never when it completes, so the runs
    /// are readable **while** a fixture tool is still working. The in-band
    /// collection canary reads them at the instant the model's first turn ends,
    /// and the failure it exists to catch is exactly the case where a fixture
    /// call is still open then: recording the handle on completion would make
    /// that read report nothing running and grade a real background run as
    /// none — which is the one reading the canary must never get wrong.
    public private(set) var observedContext: ToolContext?

    /// The runs still going on the session this log's tools ran under.
    ///
    /// `ToolContext.backgroundRuns()` behind it is Router's own spelling for the
    /// same rows; this package's word for what a row describes is a background
    /// run.
    ///
    /// - Returns: every background run, or an empty array when no fixture tool
    ///   was ever entered — in which case a scenario has a bigger problem than
    ///   its background runs, and its groundedness assertion will say so first.
    public func backgroundRuns() async -> [BackgroundRun] {
        await observedContext?.backgroundRuns() ?? []
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
    public nonisolated func recordCall<Value>(
        to path: String,
        _ body: () async throws -> Value
    ) async rethrows -> Value {
        // Read here, inside the call, because that is the only place an ambient
        // context exists — by the time a scenario asserts, every binding is
        // gone and the handle recorded here is what is left of the session's
        // background runs.
        //
        // Handed over before `body` runs, not after: see `observedContext` for
        // the scenario that reads them while a fixture call is still open.
        await observe(ToolContext.current)
        // Recorded here for the same reason, and `enteredPaths` names the run
        // that proved it necessary: a call that never comes back is invisible
        // to every record written on the way out.
        await enter(path)
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
    /// Only the first is kept: every later one names the same session's
    /// background runs, and the first is the one certain to exist by the time
    /// any scenario reads it.
    ///
    /// - Parameter ambient: the context that invocation ran under, if any.
    private func observe(_ ambient: ToolContext?) {
        guard observedContext == nil else { return }
        observedContext = ambient
    }

    /// Records that one invocation has been entered.
    ///
    /// - Parameter path: the `tools.*` path being invoked.
    private func enter(_ path: String) {
        enteredPaths.insert(path)
    }

    /// Appends one recorded invocation.
    ///
    /// - Parameter call: the invocation to record.
    private func append(_ call: ScenarioCall) {
        calls.append(call)
    }
}
