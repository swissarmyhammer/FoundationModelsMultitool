import Foundation
import FoundationModels
import FoundationModelsRouter
import os

// MARK: - The runCode mount and its work bound
//
// Router mounts `runCode` through `ToolMounting.makeWrapped` like any other
// tool, and the tool states its own mount and its own per-call work bound
// through `BackgroundTool`. This file is that declaration, the
// collect sentence the pending envelope carries — plus the cap on how many of
// the suspended JSC contexts a background run creates may be alive at once.
//
// There is exactly one background point per snippet: the outer `runCode` call.
// Inner `tools.*` calls run on the same engine under `RunBinding.innerCallMount`,
// which runs to completion, so no snippet ever branches on a pending envelope
// mid-code.

extension MultiTool: BackgroundTool {
    /// The `next` sentence of the pending envelope a background `runCode`
    /// call hands the model: call the `wait` tool with this envelope's token.
    ///
    /// This package ships the `wait` tool and owns its report, so the sentence
    /// can state the exact read. The three values it names — `complete`,
    /// `error` and `timeout` — are spliced from ``RunState`` and
    /// ``CallResult``, so they cannot drift from what `wait` reports.
    ///
    /// It never names `runCode` and never prescribes a snippet. Every mounted
    /// `runCode` call goes to the background (``mount``), so a
    /// snippet that waits on a pending token is itself a background run and
    /// hands back a fresh token. A sentence that told the model to run another
    /// snippet made it chase tokens one generation a round until it reached
    /// for the `wait` tool on its own (task `^4qcf1v9`: 21 rounds and about
    /// 1700 seconds for an eight-second run). The `wait` tool on this token
    /// returns the background snippet's result at once.
    public func collectInstruction(forCompletionToken completionToken: String) -> String {
        "Do not answer yet, and do not guess the result. "
            + "Call the wait tool with completionToken \"\(completionToken)\" to collect it. "
            + "When the report shows state \"\(RunState.complete)\" or \"\(RunState.error)\", "
            + "answer from its detail. "
            + "When the report shows result \"\(CallResult.timeout)\", "
            + "call the wait tool again with the same completionToken."
    }

    /// The mount every `runCode` call carries. It is always background.
    ///
    /// **A snippet can run for hours, so the tool states this itself.** A
    /// declared mount wins over the mount the composition site applies, and
    /// this is the declaration that makes `runCode` the backgrounder: every
    /// mounted call hands back a completion token at once, and the snippet
    /// goes on behind it. The answer cannot vary by call, by host, or by
    /// machine load, because `RunCodeArguments` carries no clock at all.
    ///
    /// The engine reads ``timeout(from:)`` ahead of the mount's own clock, so
    /// a clock here would never be consulted.
    public var mount: ToolMount? {
        ToolMount(mode: .background, timeout: nil)
    }

    /// The per-call work bound every `runCode` call carries: this package's
    /// own ceiling, `configuration.executionTimeLimit`. Every call gets the
    /// same bound, so `arguments` is unread.
    ///
    /// Always answered, never left to the mount. That limit is both this
    /// package's default work clock and its hard ceiling (see
    /// `MultiToolConfiguration.executionTimeLimit` for the full
    /// reconciliation of the two clocks). A background snippet is exactly what
    /// needs a ceiling, since nothing is blocking on it to notice that it ran
    /// away. Answering it here is what keeps the engine's clock at or under
    /// the limit the watchdog of the sandbox `MultiTool.init` runs is armed
    /// with, so the engine's own timeout is what a well-behaved suspended
    /// context meets first.
    ///
    /// It is a bound, not a promise of survival. The engine's clock and the
    /// sandbox watchdog's are not the same kind, and a snippet that keeps
    /// resetting the engine's clock is still force-terminated at the ceiling
    /// its watchdog was armed with. That absolute cap is the intended safety
    /// property, not a gap. The reconciliation named above states why.
    public func timeout(from arguments: GeneratedContent) -> TimeInterval? {
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
