import Foundation
import FoundationModels
import FoundationModelsRouter
import os

// MARK: - The runCode mount and its work bound
//
// Router mounts `runCode` through `ToolDetachment.wrapping` like any other
// tool, and the tool states its own mount and its own per-call work bound
// through `DetachmentParameterProviding`. This file is that declaration, the
// collect sentence the pending envelope carries — plus the cap on how many of
// the suspended JSC contexts a background run creates may be alive at once.
//
// There is exactly one background point per snippet: the outer `runCode` call.
// Inner `tools.*` calls run on the same engine under `RunBinding.innerCallMount`,
// which runs to completion, so no snippet ever branches on a pending envelope
// mid-code.

extension MultiTool: DetachmentParameterProviding {
    /// The `next` sentence of the pending envelope a background `runCode`
    /// call hands the model: call the `wait` tool with this envelope's token.
    ///
    /// This package ships the `wait` tool and owns its report, so the
    /// sentence states the exact read — `state` `complete` or `error` means
    /// answer from `detail`; `result` `timeout` means call `wait` again with
    /// the same token — with every value spliced from ``RunState`` and
    /// ``CallResult`` so the names cannot drift from what `wait` reports.
    ///
    /// It never names `runCode` and never prescribes a snippet. Every mounted
    /// `runCode` call goes to the background (``detachmentMount``), so a
    /// snippet that waits on a pending token is itself a background run and
    /// hands back a fresh token. A sentence that told the model to run another
    /// snippet made it chase tokens one generation a round until it reached
    /// for the `wait` tool on its own (task `^4qcf1v9`: 21 rounds and about
    /// 1700 seconds for an eight-second run). The `wait` tool on this token
    /// returns the background snippet's result at once.
    ///
    /// - Parameter completionToken: the background `runCode` call's token.
    /// - Returns: the collect directive, as plain prose.
    public func detachmentCollectInstruction(forCompletionToken completionToken: String) -> String {
        "Do not answer yet, and do not guess the result. "
            + "Call the wait tool with completionToken \"\(completionToken)\" to collect it. "
            + "When the report shows state \"\(RunState.complete)\" or \"\(RunState.error)\", "
            + "answer from its detail. "
            + "When the report shows result \"\(CallResult.timeout)\", "
            + "call the wait tool again with the same completionToken."
    }

    /// The mount every `runCode` call carries: the background, whatever mount
    /// the composition site applies.
    ///
    /// **A snippet can run for hours, so the tool states this itself.** A
    /// declared mount wins over the site, and this is the declaration that
    /// makes `runCode` the backgrounder: every mounted call hands back a
    /// completion token at once, and the snippet goes on behind it. The
    /// answer cannot vary by call, by host, or by machine load, because
    /// `RunCodeArguments` carries no clock at all.
    ///
    /// The mount carries no clock of its own. The work bound is answered per
    /// call by ``detachmentTimeout(from:)``, which the engine reads ahead of
    /// the mount, so the clock here would never be consulted.
    public var detachmentMount: DetachConfiguration? {
        DetachConfiguration(mode: .background, timeout: nil)
    }

    /// The per-call work bound every `runCode` call carries: this package's
    /// own ceiling, `configuration.executionTimeLimit`.
    ///
    /// Always answered, never left to the mount. That limit is both this
    /// package's default work clock and its hard ceiling (see
    /// `MultiToolConfiguration.executionTimeLimit` for the full
    /// reconciliation). A background snippet is exactly what needs a ceiling,
    /// since nothing is blocking on it to notice that it ran away. Answering
    /// it here is what keeps the engine's clock at or under the limit the
    /// watchdog of the sandbox `MultiTool.init` runs is armed with, so the
    /// engine's own timeout is what a well-behaved suspended context meets
    /// first. That holds for an interpreter injected into `MultiTool.init`
    /// too: it is re-armed from the same ceiling this bound comes from
    /// (`Interpreter.withTimeLimit(_:)`), so the two sides cannot disagree.
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
    /// - Parameter arguments: the call's arguments as opaque
    ///   `GeneratedContent`. Unread: every `runCode` call gets the same bound.
    /// - Returns: this package's bounded work clock.
    public func detachmentTimeout(from arguments: GeneratedContent) -> TimeInterval? {
        configuration.executionTimeLimit
    }
}

// MARK: - The cap on live contexts

extension MultiTool {
    /// How many of one `MultiTool`'s `runCode` contexts are live right now.
    ///
    /// A live context is a `runCode` call between entering
    /// `call(arguments:)` and leaving it — which, once the call has handed
    /// back its pending envelope, means a *suspended* JSC context: the
    /// background run is the only way a call stays live after it answered.
    /// Each one holds a real JS context, its pending promises, and the thread
    /// its run occupies, so the set is capped rather than left to grow
    /// (eventplan.md § "The constraint boundary, and the escape hatch"; the
    /// cap itself is `MultiToolConfiguration.liveContextLimit`).
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
