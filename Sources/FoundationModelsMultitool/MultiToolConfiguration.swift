import Foundation
import FoundationModelsExtras

/// plan.md M10 — "Limits tuned + configurable": the knobs `MultiTool` uses to
/// bound one `runCode` call.
///
/// No knob limits the number of calls that run or wait at the same time. A
/// run that waits for a `tools.*` call holds no thread, only its JSC context
/// in memory (see `JSCInterpreter`), so the machine bounds that number, and
/// no constant in code does.
///
/// This type carries no turn budget. A host mounts the vended tools on a
/// session of its own (for example a Router session), and that session's own
/// tool-calling loop owns turn budgeting. The retired `MultiToolAgent` knobs
/// `maxAgentTurns` and `maxRepairTurns` went with it, and only the
/// `runCode`-sandbox limits stay.
public struct MultiToolConfiguration: Sendable, Equatable {
    /// The tool-level timeout, in seconds, of a single `runCode` call. It is
    /// the one clock of `runCode`: the call answers it to the engine as its
    /// work bound (`MultiTool.timeout(from:)`). The default is
    /// ``defaultExecutionTimeLimit``.
    ///
    /// A mounted `runCode` call that does not settle inside
    /// ``inlineSettleGrace`` answers its pending envelope, and the snippet
    /// goes on in the background, so the suspended JSC context lives
    /// past the call. This clock bounds that background snippet too.
    ///
    /// Each progress event of the snippet resets the clock. Thus a snippet
    /// that reports progress inside each window keeps running, and a snippet
    /// that stops its progress ends one window after its last event.
    ///
    /// The engine enforces the bound through the same cancellation path a
    /// cancelled `Task` uses: `MultiTool` awaits `Interpreter.run`, and the
    /// cancellation of that task cancels the run — a job that executes JS
    /// stops at its next watchdog poll, and a run that waits ends at once.
    /// The interpreter has no clock of its own, thus this cancellation is
    /// the only way the clock reaches a running snippet.
    public let executionTimeLimit: TimeInterval

    /// How long a `runCode` call waits for its own snippet before it answers
    /// with a completion token.
    ///
    /// **Why a `runCode` call waits at all.** Every mounted call goes to the
    /// background (`MultiTool.mount`), so the model gets a token, ends its
    /// answer, and pays one more submission to read the result from the mail.
    /// Most snippets are short — one file read, one small edit, one `tools.*`
    /// call — and for those the token costs more than the work. A wait here
    /// gives the model the result in the tool output it already has, and no
    /// mail comes for that run.
    ///
    /// A snippet still running when this elapses is not affected. The call
    /// answers with the pending envelope, the snippet goes on in the
    /// background, and its result comes back to the session as mail. So the
    /// cost of a long snippet is this delay, one time, and nothing else.
    ///
    /// The same value is the wait of each inner `tools.*` call of a background
    /// tool, for example `tools.shell.execute`. An inner call that settles in
    /// it gives the snippet its own result, so the snippet uses it at once.
    ///
    /// The wait is not a second work clock. It never cancels a snippet and it
    /// never shortens ``executionTimeLimit``.
    public let inlineSettleGrace: TimeInterval

    /// Maximum length, in characters, of a snippet's serialized return value
    /// — see `ResultRendererLimits.returnValueCharacterLimit`.
    public let returnValueCharacterLimit: Int

    /// Maximum length, in characters, of a snippet's joined `console.log`
    /// output — see `ResultRendererLimits.consoleCharacterLimit`.
    public let consoleCharacterLimit: Int

    /// The stock tool-level timeout of one `runCode` call, in seconds — see
    /// ``executionTimeLimit``.
    ///
    /// 120 seconds. This package owns the value. The hosting engine of
    /// FoundationModelsExtras has no stock tool timeout: a hosted tool has a
    /// timeout only when the tool states one.
    /// `runCode` states this one.
    public static let defaultExecutionTimeLimit: TimeInterval = 120

    /// The stock wait before a `runCode` call answers — see
    /// ``inlineSettleGrace``.
    ///
    /// It is `ToolMount.defaultInlineSettleGrace` of FoundationModelsExtras,
    /// and this package states no number of its own. Thus `runCode`, every
    /// other background tool of a session, and each inner `tools.*` call of a
    /// snippet wait for the same time when no host changes it. The rule is
    /// the decision of the user: a background call goes to the background
    /// only when it takes longer than this wait.
    ///
    /// The cost: while the wait runs, the call is in-band, so a snippet that
    /// does not settle holds the model for up to this time
    /// (Router's `generation-queue.md` §5.5 rule 5). A host that needs the
    /// model free sooner sets a smaller value.
    public static let defaultInlineSettleGrace: TimeInterval = ToolMount.defaultInlineSettleGrace

    /// The stock limits. ``defaultExecutionTimeLimit`` and
    /// ``defaultInlineSettleGrace`` give the sizing for the work clock and the
    /// wait. The two character caps are sized on
    /// `ResultRendererLimits.defaultReturnValueCharacterLimit` and
    /// `ResultRendererLimits.defaultConsoleCharacterLimit`, which state why
    /// each number is what it is.
    public static let `default` = MultiToolConfiguration()

    /// Creates a hardening configuration. Each limit is clamped up to at
    /// least `0`. A stray negative value in a host's configuration thus
    /// cannot disable a bound or crash a `runCode` turn.
    ///
    /// - Parameters:
    ///   - executionTimeLimit: see ``executionTimeLimit``.
    ///   - inlineSettleGrace: see ``inlineSettleGrace``.
    ///   - returnValueCharacterLimit: see ``returnValueCharacterLimit``.
    ///   - consoleCharacterLimit: see ``consoleCharacterLimit``.
    public init(
        executionTimeLimit: TimeInterval = MultiToolConfiguration.defaultExecutionTimeLimit,
        inlineSettleGrace: TimeInterval = MultiToolConfiguration.defaultInlineSettleGrace,
        returnValueCharacterLimit: Int = ResultRendererLimits.default.returnValueCharacterLimit,
        consoleCharacterLimit: Int = ResultRendererLimits.default.consoleCharacterLimit
    ) {
        self.executionTimeLimit = max(0, executionTimeLimit)
        self.inlineSettleGrace = max(0, inlineSettleGrace)
        self.returnValueCharacterLimit = max(0, returnValueCharacterLimit)
        self.consoleCharacterLimit = max(0, consoleCharacterLimit)
    }

    /// The `ResultRenderer` caps this configuration implies. It wraps the two
    /// character limits, so `ResultRenderer` does not have to know about this
    /// type at all.
    ///
    /// The ownership rule this wrapper keeps: plan.md's caps are
    /// `ResultRenderer`'s to ENFORCE, and this configuration only carries the
    /// numbers `MultiTool` hands it. Do not put cap logic in this type.
    public var resultLimits: ResultRendererLimits {
        ResultRendererLimits(
            returnValueCharacterLimit: returnValueCharacterLimit,
            consoleCharacterLimit: consoleCharacterLimit
        )
    }
}
