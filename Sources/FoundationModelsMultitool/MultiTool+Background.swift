import Foundation
import FoundationModels
import FoundationModelsExtras
import os

// MARK: - The runCode mount and its work bound
//
// A Router session mounts `runCode` through `ToolMounting.makeWrapped` of
// FoundationModelsExtras like any other tool, and the tool states its own
// mount and its own per-call work bound through `BackgroundTool`. This file
// is that declaration, the
// collect sentence the pending envelope carries — plus the cap on how many of
// the suspended JSC contexts a background run creates may be alive at once.
//
// There is exactly one background point per snippet: the outer `runCode` call.
// Inner `tools.*` calls run on the same engine under `RunBinding.innerCallMount`,
// which runs to completion, so no snippet ever branches on a pending envelope
// mid-code.

extension MultiTool: BackgroundTool {
    /// The `next` sentence of the pending envelope a background `runCode`
    /// call hands the model: end the answer, and the result comes back as a
    /// new message.
    ///
    /// **The session delivers a settled run as mail.** Router puts the
    /// terminal event of a background run into the session outbox, and that
    /// mail starts the next submission of the session
    /// (`generation-queue.md` §5.5 rule 1). Thus the model does not collect
    /// the run. It ends its answer, and the next message it gets carries the
    /// result. A wait inside the submission holds the model for every
    /// session on it, and a run on the same model can never settle inside
    /// that wait (§5.5). That is why this package mounts no `wait` tool.
    ///
    /// It never names `runCode` and never prescribes a snippet. Every mounted
    /// `runCode` call goes to the background (``mount``), so a snippet that
    /// waits on a pending token is itself a background run and hands back a
    /// fresh token. A sentence that told the model to run another snippet
    /// made it chase tokens one generation a round (task `^4qcf1v9`: 21
    /// rounds and about 1700 seconds for an eight-second run).
    ///
    /// The sentence names the token, because the mail that comes back names
    /// the run by the same token.
    public func collectInstruction(forCompletionToken completionToken: String) -> String {
        "The snippet is still running in the background, and this is not its result. "
            + "Do not guess the result. End your answer now. "
            + "When the snippet finishes, its result comes back to you as a new message "
            + "with completionToken \"\(completionToken)\", and you answer from that result then."
    }

    /// The `next` sentence of the envelope a `runCode` call hands the model
    /// when the snippet settled inside ``inlineSettleGrace``: the result is
    /// beside the sentence, so answer from it now.
    ///
    /// It is the counterpart of ``collectInstruction(forCompletionToken:)``,
    /// and it says the opposite thing for the opposite condition. The pending
    /// sentence tells the model to end its answer and read the result from a
    /// later message. This one tells it that no later message comes: the run
    /// plane of FoundationModelsExtras withdraws the staged mail of a run
    /// whose result goes out inline (`BackgroundToolRunner.settledEnvelope`),
    /// so the result is in this tool output and nowhere else.
    ///
    /// The last clause is there because a model that holds the result has
    /// still answered "it will come back to me later" (task `wnfzwxg`).
    public func resultInstruction(forCompletionToken completionToken: String) -> String {
        "The snippet is complete and its result is the detail field above. "
            + "Answer from that result now. "
            + "No other message about completionToken \"\(completionToken)\" comes, "
            + "so never reply that the result will arrive later."
    }

    /// How long a `runCode` call waits for its own snippet before it answers
    /// with a completion token: `configuration.inlineSettleGrace`.
    ///
    /// **Most snippets are short, and a token for a short snippet is pure
    /// cost.** One file read, one small edit, one `tools.*` call: each is over
    /// in well under a second. Without this wait the model ends its answer and
    /// pays one more submission to read the result from the mail. With this
    /// wait the common snippet answers with its own result, and the mail is
    /// left for the snippet that really is long.
    ///
    /// A snippet still running when the wait elapses answers with the pending
    /// envelope, exactly as every `runCode` call did before. Nothing is
    /// cancelled and no work is lost. The cost is the delay itself, and it is
    /// an in-band wait: it holds the model for every session on it
    /// (`generation-queue.md` §5.5 rule 5).
    ///
    /// The host sets the value, or takes
    /// `MultiToolConfiguration.defaultInlineSettleGrace`.
    public var inlineSettleGrace: TimeInterval? {
        configuration.inlineSettleGrace
    }

    /// The mount every `runCode` call carries. It is always background.
    ///
    /// **A snippet can run for hours, so the tool states this itself.** A
    /// declared mount wins over the mount the composition site applies, and
    /// this is the declaration that makes `runCode` the backgrounder: every
    /// mounted call runs its snippet in the background. The call waits for
    /// the snippet for ``inlineSettleGrace`` only, and then it hands back a
    /// completion token while the snippet goes on behind it. The model cannot
    /// change the mount or the wait, because `RunCodeArguments` carries no
    /// clock at all.
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
    /// hands a model: it names the cap it hit and the two ways that make room
    /// for this call. A run that finishes makes room, and its result comes
    /// back to the session as mail when the model ends its answer. A run that
    /// `cancel()` stops makes room at once. The text names no `wait()`: a
    /// snippet that waits holds the model for every session on it
    /// (`generation-queue.md` §5.5).
    ///
    /// - Returns: the error `ResultRenderer` renders as the call's output.
    static func liveContextCapError(limit: Int) -> InterpreterError {
        InterpreterError(
            kind: .exception,
            message: "Too many runCode snippets are running at once (limit \(limit)). "
                + "Do not start another now. End your answer: the result of each running snippet "
                + "comes back to you as a new message when it finishes. status() lists the "
                + "completion token of each running snippet, and cancel(completionToken) stops "
                + "one that you do not need."
        )
    }
}
