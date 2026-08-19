import Foundation
import FoundationModels
import FoundationModelsRouter
import os

// MARK: - The runCode envelope's two clocks (eventplan.md § "Elevation:
// waitSeconds and the completion token")
//
// Router's native session mount wraps `runCode` in `DetachingTool` like any
// other tool, and the engine reads each call's own clocks back out of the
// opaque `GeneratedContent` through `DetachmentParameterProviding`. This file is
// that reading — plus the cap on how many of the suspended JSC contexts
// elevation creates may be alive at once.
//
// There is exactly one elevation point per snippet: the outer `runCode` call.
// Inner `tools.*` calls run on the same engine with elevation off (see
// `RunBinding`), so no snippet ever branches on a pending envelope mid-code.

extension MultiTool: DetachmentParameterProviding {
    /// The per-call clocks every `runCode` call carries.
    ///
    /// **The wait clock is always zero, and no call can raise it.**
    /// `DetachConfiguration.waitSeconds`' own documentation defines `0` as
    /// detach-immediately, so answering zero here is what makes `runCode` the
    /// backgrounder: it hands back a completion token every time, whatever the
    /// mount's own wait clock says (task `^cv98vff`). The arguments are no
    /// longer read for it — `RunCodeArguments` carries no clocks at all — so
    /// the answer cannot vary by call, by host, or by machine load.
    ///
    /// `timeout` is still answered, never left to the mount, and always
    /// bounded by `configuration.executionTimeLimit`: that limit is both this
    /// package's default work clock and its hard ceiling (see
    /// `MultiToolConfiguration.executionTimeLimit` for the full
    /// reconciliation). A backgrounded snippet is exactly what needs a
    /// ceiling, since nothing is blocking on it to notice that it ran away.
    /// Answering it here is what keeps the engine's clock at or under the
    /// limit the watchdog of the sandbox `MultiTool.init` runs is armed with,
    /// so the engine's own timeout is what a well-behaved suspended context
    /// meets first. That holds for an interpreter injected into
    /// `MultiTool.init` too: it is re-armed from the same ceiling this bound
    /// comes from (`Interpreter.withTimeLimit(_:)`), so the two sides cannot
    /// disagree.
    ///
    /// It is a bound, not a promise of survival. The two clocks are not the
    /// same kind: the engine's timeout resets on every progress event, while
    /// the watchdog measures from sandbox creation and nothing resets it
    /// (`WatchdogState.runStart` is a `let`; `rearm()` re-arms the poll
    /// interval, not the deadline). A snippet that keeps resetting the
    /// engine's clock — by reporting progress, or by suspending on `elicit()` —
    /// therefore still meets the configured ceiling its sandbox's watchdog
    /// was armed with, and is force-terminated there. The absolute cap is the
    /// intended safety property, not a gap.
    ///
    /// **The conformance stays, although nothing is read from the arguments.**
    /// It has two jobs left, and both are answers this package must give
    /// rather than inherit: forcing the wait clock to zero against whatever
    /// the mount configured, and holding the work clock at this package's own
    /// ceiling. Dropping it would put both back in the mount's hands.
    ///
    /// - Parameter arguments: the call's arguments as opaque
    ///   `GeneratedContent`. Unread: every `runCode` call gets the same two
    ///   answers, because every one of them backgrounds.
    /// - Returns: a zero wait clock, and this package's bounded work clock.
    public func detachmentClocks(
        from arguments: GeneratedContent
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        (detachImmediatelySeconds, configuration.executionTimeLimit)
    }

    /// The wait clock every `runCode` call reports: detach immediately.
    ///
    /// Named rather than written as a bare `0` at the one site that answers
    /// it, because the value is the whole rule — see ``detachmentClocks(from:)``.
    private var detachImmediatelySeconds: TimeInterval { 0 }
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
    /// hands a model: it names the cap it hit and the three globals that
    /// collect a background run, because collecting one is exactly what makes
    /// room for this call.
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
