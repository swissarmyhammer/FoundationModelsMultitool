import Foundation
import FoundationModels
import FoundationModelsRouter
import os

// MARK: - The runCode envelope's two clocks (eventplan.md § "Elevation:
// waitSeconds and the completion token")
//
// Router's native session mount wraps `runCode` in `ElevatingTool` like any
// other tool, and the engine reads each call's own clocks back out of the
// opaque `GeneratedContent` through `ElevationParameterProviding`. This file is
// that reading — plus the cap on how many of the suspended JSC contexts
// elevation creates may be alive at once.
//
// There is exactly one elevation point per snippet: the outer `runCode` call.
// Inner `tools.*` calls run on the same engine with elevation off (see
// `RunBinding`), so no snippet ever branches on a pending envelope mid-code.

extension MultiTool: ElevationParameterProviding {
    /// The per-call clocks this `runCode` envelope carries.
    ///
    /// `waitSeconds` crosses untouched — including `0`, which detaches the
    /// call immediately — because the wait clock belongs to the caller, and a
    /// call that supplies none leaves it to the mount (a `nil` here is the
    /// engine's own "use the wrap-time configuration" signal).
    ///
    /// `timeout` is always answered, never left to the mount, and always
    /// bounded by `configuration.executionTimeLimit`: that limit is both this
    /// package's default work clock and its hard ceiling (see
    /// `MultiToolConfiguration.executionTimeLimit` for the full
    /// reconciliation). Answering it here is what keeps the engine's clock at
    /// or under the limit the watchdog of the sandbox `MultiTool.init` runs
    /// is armed with, so the engine's own timeout is what a well-behaved
    /// suspended context meets first. That holds for an interpreter injected
    /// into `MultiTool.init` too: it is re-armed from the same ceiling this
    /// bound comes from (`Interpreter.withTimeLimit(_:)`), so the two sides
    /// cannot disagree.
    ///
    /// It is a bound, not a promise of survival. The two clocks are not the
    /// same kind: the engine's timeout resets on every progress event, while
    /// the watchdog measures from sandbox creation and nothing resets it
    /// (`WatchdogState.runStart` is a `let`; `rearm()` re-arms the poll
    /// interval, not the deadline). A snippet that keeps resetting the
    /// engine's clock — by reporting progress, or by parking on `elicit()` —
    /// therefore still meets the configured ceiling its sandbox's watchdog
    /// was armed with, and is force-terminated there. The absolute cap is the
    /// intended safety property, not a gap.
    ///
    /// - Parameter arguments: the call's arguments as opaque
    ///   `GeneratedContent` — the same content `RunCodeArguments` was decoded
    ///   from.
    /// - Returns: the call's wait clock, or `nil` when it supplies none; and
    ///   its bounded work clock.
    public func elevationClocks(
        from arguments: GeneratedContent
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        (
            try? arguments.value(TimeInterval.self, forProperty: RunCodeArguments.waitSecondsProperty),
            bounded(timeout: try? arguments.value(TimeInterval.self, forProperty: RunCodeArguments.timeoutProperty))
        )
    }

    /// Bounds one call's requested work clock by this tool's configured
    /// ceiling.
    ///
    /// - Parameter timeout: the `timeout` the envelope carried, or `nil` when
    ///   it carried none.
    /// - Returns: the requested value clamped to `0...executionTimeLimit`, or
    ///   the ceiling itself when the envelope asked for nothing.
    private func bounded(timeout: TimeInterval?) -> TimeInterval {
        let ceiling = configuration.executionTimeLimit
        guard let timeout else { return ceiling }
        return min(max(0, timeout), ceiling)
    }
}

extension RunCodeArguments {
    /// The property name the wait clock is read back out of `GeneratedContent`
    /// under — the encoded spelling of ``waitSeconds``.
    static let waitSecondsProperty = "waitSeconds"

    /// The property name the work clock is read back out of
    /// `GeneratedContent` under — the encoded spelling of ``timeout``.
    static let timeoutProperty = "timeout"
}

// MARK: - The cap on live contexts

extension MultiTool {
    /// How many of one `MultiTool`'s `runCode` contexts are live right now.
    ///
    /// A live context is a `runCode` call between entering
    /// `call(arguments:)` and leaving it — which, past its wait window, means
    /// a *suspended* JSC context: elevation is the only way a call stays live
    /// once it has handed back a pending envelope. Each one holds a real JS
    /// context, its pending promises, and the thread its run occupies, so the
    /// set is capped rather than left to grow (eventplan.md § "The constraint
    /// boundary, and the escape hatch"; the cap itself is
    /// `MultiToolConfiguration.liveContextLimit`).
    ///
    /// A reference type because every copy of the `MultiTool` value that owns
    /// it shares the one interpreter whose contexts it counts. Guarded by
    /// `OSAllocatedUnfairLock` rather than modelled as an `actor` because both
    /// operations are synchronous decisions on a single `Int`, taken on the
    /// call's own thread, with nothing to await — the same choice
    /// `JSCInterpreter`'s own `WatchdogState` makes.
    final class LiveContextCounter: Sendable {
        /// The count of live contexts.
        private let live = OSAllocatedUnfairLock(initialState: 0)

        /// Claims one live context, if the cap leaves room for it.
        ///
        /// - Parameter limit: the most contexts that may be live at once.
        /// - Returns: `true` when the context was claimed, and the caller owes
        ///   a matching ``release()``; `false` when the cap is already full
        ///   and the caller must not run.
        func claim(upTo limit: Int) -> Bool {
            live.withLock { count in
                guard count < limit else { return false }
                count += 1
                return true
            }
        }

        /// Gives back one claimed live context.
        func release() {
            live.withLock { $0 -= 1 }
        }
    }

    /// The repairable, in-band failure a `runCode` call beyond the live-context
    /// cap reports.
    ///
    /// Phrased as repair instructions, like every other error this package
    /// hands a model: it names the cap it hit and the three run-plane globals
    /// that collect a parked snippet, because collecting one is exactly what
    /// makes room for this call.
    ///
    /// - Parameter limit: the configured cap the call would have exceeded.
    /// - Returns: the error `ResultRenderer` renders as the call's output.
    static func liveContextCapError(limit: Int) -> InterpreterError {
        InterpreterError(
            kind: .exception,
            message: "Too many runCode snippets are running at once (limit \(limit)). "
                + "Collect one before starting another: status() lists every pending run's "
                + "completion token, wait(completionToken, seconds) collects a run's result, and "
                + "cancel(completionToken) ends one you no longer need."
        )
    }
}
