import Foundation
import FoundationModels
import FoundationModelsExtras

// MARK: - The runCode mount and its work bound
//
// A Router session mounts `runCode` through `ToolMounting.makeWrapped` of
// FoundationModelsExtras like any other tool, and the tool states its own
// mount and its own per-call work bound through `BackgroundTool`. This file
// is that declaration and the collect sentence the pending envelope carries.
// No number limits how many runs are alive at once: a run that waits holds
// no thread, only its JSC context in memory (see `JSCInterpreter`).
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
    /// It never prescribes a snippet, and it names `runCode` only to forbid a
    /// call. Every mounted `runCode` call goes to the background (``mount``),
    /// so a snippet that waits on a pending token is itself a background run
    /// and hands back a fresh token. A sentence that told the model to run
    /// another snippet made it chase tokens one generation a round (task
    /// `^4qcf1v9`: 21 rounds and about 1700 seconds for an eight-second run).
    /// And with no word against it, a model still called `runCode` to wait:
    /// in one SWE-bench run, 133 of 348 calls were `return "waiting1"` to
    /// `return "waiting130"` (task `^cf57dtd`). Thus the last sentence forbids
    /// a call that waits or checks.
    ///
    /// The sentence names the token, because the mail that comes back names
    /// the run by the same token.
    public func collectInstruction(forCompletionToken completionToken: String) -> String {
        "The snippet is still running in the background, and this is not its result. "
            + "Do not guess the result. End your answer now. "
            + "When the snippet finishes, its result comes back to you as a new message "
            + "with completionToken \"\(completionToken)\", and you answer from that result then. "
            + "Do not call runCode to wait or to check; the result comes to you without a call."
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
    /// The mount states no clock. The one clock of a `runCode` call is the
    /// tool-level timeout of ``timeout(from:)``, and the engine reads it ahead
    /// of the clock of the mount. Thus a clock here would never be consulted.
    public var mount: ToolMount? {
        ToolMount(mode: .background, timeout: nil)
    }

    /// The tool-level timeout every `runCode` call carries:
    /// `configuration.executionTimeLimit`. Every call gets the same timeout,
    /// so `arguments` is unread.
    ///
    /// Always answered, never left to the mount. It is the one clock of a
    /// `runCode` call, and the interpreter has no clock of its own (see
    /// `MultiToolConfiguration.executionTimeLimit`). A background snippet is
    /// exactly what needs a clock, since nothing is blocking on it to notice
    /// that it ran away.
    ///
    /// Each progress event of the snippet resets the clock. When the clock
    /// fires, the engine cancels the run, and the call ends as timed out.
    public func timeout(from arguments: GeneratedContent) -> TimeInterval? {
        configuration.executionTimeLimit
    }
}
