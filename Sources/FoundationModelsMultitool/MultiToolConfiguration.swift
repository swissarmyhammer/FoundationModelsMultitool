import Foundation
import FoundationModelsExtras

/// plan.md M10 — "Limits tuned + configurable": the knobs `MultiTool` uses to
/// bound one `runCode` call and the number of calls that stay live.
///
/// This type carries no turn budget. A host mounts the vended tools on a
/// session of its own (a Router session in the sample CLI), and that
/// session's own tool-calling loop owns turn
/// budgeting. The retired `MultiToolAgent` knobs `maxAgentTurns` and
/// `maxRepairTurns` went with it, and only the `runCode`-sandbox limits stay.
public struct MultiToolConfiguration: Sendable, Equatable {
    /// Wall-clock ceiling, in seconds, on a single `runCode` snippet's work.
    /// It is also the per-call work bound `runCode` answers the engine (see
    /// `MultiTool.timeout(from:)`).
    ///
    /// A mounted `runCode` call that does not settle inside
    /// ``inlineSettleGrace`` answers its pending envelope, and the snippet
    /// goes on in the background, so the suspended JSC context lives
    /// past the call. This value arms the watchdog of every sandbox
    /// `MultiTool.init` runs (`Interpreter.withTimeLimit(_:)`), and it must
    /// never be a second clock that races the engine's. `runCode` states this
    /// same value to the engine as its work bound (`MultiTool.timeout(from:)`),
    /// so the two clocks come from one value. The default is
    /// ``defaultExecutionTimeLimit``.
    ///
    /// The engine enforces its own bound through the same cancellation path a
    /// cancelled `Task` uses: `MultiTool` wraps the run in a
    /// `withTaskCancellationHandler` whose `onCancel` sets a flag, and the
    /// sandbox polls that flag as `Interpreter.run`'s `isCancelled` hook. That
    /// is how the engine's clock reaches a running snippet at all.
    ///
    /// The two clocks are not the same kind. The engine resets its clock on
    /// every progress event. This one does not: the `WatchdogState` measures
    /// from sandbox creation, and neither progress nor a suspension on
    /// `elicit()` moves that reference point (`deadline` is a `let`, and
    /// `rearm()` re-arms the poll interval, not the deadline). So a snippet
    /// that keeps resetting the engine's clock is force-terminated here, at
    /// this ceiling. That absolute cap is the intended safety property, and
    /// it is why progress reports cannot keep a suspended context alive
    /// without end.
    ///
    /// The arming covers an injected sandbox too: an `interpreter:` a caller
    /// hands to `MultiTool.init` is re-armed with this ceiling. So injection
    /// cannot put a second, different limit under a `runCode` call — a plain
    /// `JSCInterpreter()`, whose own stock limit is 5 seconds, is armed from
    /// here like any other.
    public let executionTimeLimit: TimeInterval

    /// How many `runCode` snippets may be live at once. A further call is
    /// refused with a repairable in-band error.
    ///
    /// A snippet stays live after its call has answered only in the background
    /// (`LiveContextCounter`: the background run is the only way a call stays
    /// live after it answered), so this is the cap on suspended JSC contexts
    /// (eventplan.md § "The constraint boundary, and the escape hatch").
    ///
    /// Each one holds a real JS context and the thread its run occupies. A
    /// model that has backgrounded this many snippets has lost track of them,
    /// and the error tells it to end its answer, so that the results come back
    /// as mail, or to stop one with `cancel()`, instead of starting another.
    public let liveContextLimit: Int

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
    /// The wait is not a second work clock. It never cancels a snippet and it
    /// never shortens ``executionTimeLimit``.
    public let inlineSettleGrace: TimeInterval

    /// Maximum length, in characters, of a snippet's serialized return value
    /// — see `ResultRendererLimits.returnValueCharacterLimit`.
    public let returnValueCharacterLimit: Int

    /// Maximum length, in characters, of a snippet's joined `console.log`
    /// output — see `ResultRendererLimits.consoleCharacterLimit`.
    public let consoleCharacterLimit: Int

    /// The stock ceiling on one `runCode` snippet's work, in seconds — see
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
    /// Five seconds. It is long enough for the short snippets that are the
    /// common case, and for many longer ones, to give their result in the
    /// call itself. The cost: while the wait runs, the call is in-band, so a
    /// snippet that does not settle holds the model for up to this time. A
    /// host that needs the model free sooner sets a smaller value.
    ///
    /// Router's `generation-queue.md` §5.5 rule 5 says to keep this wait
    /// small, because it holds the model for every session on it. Five
    /// seconds is a decision of the user (task `^q4jrnd0`), and it is the
    /// value this package states against that rule.
    public static let defaultInlineSettleGrace: TimeInterval = 5

    /// The stock number of live `runCode` contexts — see ``liveContextLimit``
    /// for why a handful, rather than an unbounded set, is the right shape.
    public static let defaultLiveContextLimit = 8

    /// The stock limits. ``executionTimeLimit`` and ``defaultLiveContextLimit``
    /// give the sizing for the work clock and the live-context cap. The two
    /// character caps are sized on
    /// `ResultRendererLimits.defaultReturnValueCharacterLimit` and
    /// `ResultRendererLimits.defaultConsoleCharacterLimit`, which state why
    /// each number is what it is.
    public static let `default` = MultiToolConfiguration()

    /// Creates a hardening configuration. Each limit is clamped into its valid
    /// range: `liveContextLimit` up to at least `1`, and each other limit up
    /// to at least `0`. A stray negative value in a host's configuration thus
    /// cannot disable a bound or crash a `runCode` turn.
    public init(
        executionTimeLimit: TimeInterval = MultiToolConfiguration.defaultExecutionTimeLimit,
        liveContextLimit: Int = MultiToolConfiguration.defaultLiveContextLimit,
        inlineSettleGrace: TimeInterval = MultiToolConfiguration.defaultInlineSettleGrace,
        returnValueCharacterLimit: Int = ResultRendererLimits.default.returnValueCharacterLimit,
        consoleCharacterLimit: Int = ResultRendererLimits.default.consoleCharacterLimit
    ) {
        self.executionTimeLimit = max(0, executionTimeLimit)
        self.liveContextLimit = max(1, liveContextLimit)
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
