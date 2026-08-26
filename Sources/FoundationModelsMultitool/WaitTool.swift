import Foundation
import FoundationModels
import FoundationModelsRouter

/// The arguments `wait` accepts: which run to wait for, and how long to wait
/// before reporting back instead of continuing to block.
@Generable
public struct WaitArguments {
    /// One run's completion token, or `nil` to wait for every pending run.
    @Guide(
        description: "Optional. The completion token of one long-running call to wait for. Omit it to "
            + "wait for every call this session still has running."
    )
    public var completionToken: String?

    /// The most seconds to block before reporting what is still running.
    @Guide(
        description: "Optional. The most seconds to block before reporting back. This is a safety "
            + "bound so a stuck call cannot hold the turn forever — it is not an estimate of how long "
            + "the work takes, and a call that finishes sooner returns sooner. Omit it to use the "
            + "host's own bound."
    )
    public var timeout: Double?

    /// Creates the arguments for one `wait` call.
    ///
    /// Explicit for the same reason as every other public `@Generable` type's
    /// initializer in this package (e.g. `RunCodeArguments.init`): a `public`
    /// struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameters:
    ///   - completionToken: one run's token, or `nil` for every pending run.
    ///   - timeout: the bound in seconds, or `nil` for the host's own.
    public init(completionToken: String? = nil, timeout: Double? = nil) {
        self.completionToken = completionToken
        self.timeout = timeout
    }
}

/// The tool a model calls when it has decided to block until running work
/// finishes.
///
/// **Why this is a tool and not something a snippet does.** Waiting used to be
/// a `wait(completionToken, seconds)` global inside the `runCode` sandbox, and
/// that shape asked the model for a number it cannot know: how long someone
/// else's work will take. Every value it can write is wrong — too short burns a
/// turn, too long stalls one — and a gated run measured the consequence, writing
/// `return await wait(token, 60)` seven times without ever collecting anything
/// (tasks `2w9vbkm`, `h773bed`).
///
/// The difference is what the model supplies. A snippet-level wait asked it to
/// *predict a duration*. This tool asks it to *declare an intent to block*, and
/// `timeout` is a safety bound rather than a forecast: work that finishes early
/// returns early, and the bound exists only so a stuck run cannot hold a turn
/// open forever. The host does the looping, which is the party that can — code
/// can wait until settled, a model can only guess and re-ask.
///
/// It is also visible. A `wait` call appears in the transcript and in a UI as
/// itself, where the same decision buried in snippet source did not.
///
/// **The two surfaces.** On the streaming surface no tool holds the turn: slow
/// work runs in the background and its result arrives. This tool is how a model
/// that genuinely cannot proceed without a result chooses to stop and wait for
/// one. A caller that wants blocking for its own sake calls
/// `RoutedSession.respond(to:)` instead, which drains everything — that is
/// FoundationModels semantics and needs no tool.
///
/// **No session, nothing to wait for.** Like the sandbox globals, this reads
/// the ambient `ToolContext`; constructed and called outside any session it
/// reports that there is nothing to wait for rather than trapping, which is the
/// mode every unit suite in this package runs in.
// MARK: - `wait` never backgrounds itself

extension WaitTool: DetachmentParameterProviding {
    /// The mount a `wait` call carries: run to completion, under no clock.
    ///
    /// **There are two ways for `wait` to return, and this is what keeps a
    /// third from existing.** It returns when the run finishes, or when the
    /// bound the caller passed elapses. Mounted by a site that backgrounds, a
    /// `wait` call would *background itself* — handing the model a completion
    /// token for its own wait, which is the exact regress this tool was built
    /// to end (task `^2w9vbkm`, and `^w8dzvee` D5). A declared mount wins
    /// over the site, and this declaration is what keeps the site's choice
    /// away from this tool.
    ///
    /// The mount is `runToCompletionMount`, for the same reason
    /// `SearchToolsTool` takes it: neither question a mount answers has a
    /// bounded answer here. The mode asks whether this call hands back a
    /// handle — never, since blocking is the whole point of a `wait`. The
    /// work clock asks how long it may run before being cancelled and
    /// reported failed — no limit, because the caller's own `timeout` is the
    /// only bound in this design, and a host clock firing under it would
    /// report a timeout on its own schedule rather than the caller's.
    ///
    /// A `wait` that backgrounded itself would be self-defeating in a way
    /// worth stating plainly: the model calls it to collect a token, and a
    /// backgrounding `wait` would answer with a second token to collect.
    public var detachmentMount: DetachConfiguration? { .runToCompletionMount }
}

public struct WaitTool: Tool {
    /// This tool's `Tool`-protocol name, always `"wait"`.
    public let name = "wait"

    /// This tool's usage instructions, as the model reads them.
    ///
    /// States when to call it and what comes back, and deliberately never
    /// suggests a number of seconds: the bound is optional and the host has
    /// one, so a model reading this has no reason to invent a duration.
    public let description = """
        wait blocks until long-running calls finish, and hands back what they returned. Call it only
        when you cannot continue without a result you have not been given yet. With no arguments it
        waits for every call this session still has running; with a completionToken it waits for that
        one. Each finished call comes back with a `state` — `\(RunState.complete)` when it delivered
        its result and `\(RunState.error)` when it did not — and a `detail`, which is the result and
        is what to answer from. A call still running when the bound passes comes back with a `result`
        of `\(CallResult.timeout)`, which means it is still going and nothing has failed: call wait
        again if you still need it.
        """

    /// Creates the tool.
    public init() {}

    /// Where this tool's call boundaries are recorded — see ``CallTrace``.
    ///
    /// A `wait` call is *designed* to block, and it declares both of its own
    /// clocks unbounded, so blocking forever and working correctly look
    /// identical from every angle except this one. The entry line names the
    /// token it is waiting on, which is what turns "the turn stopped" into
    /// "the turn is waiting on this run."
    private static let trace = CallTrace(category: "Wait")

    /// Waits for the named run, or for every pending run, and reports what
    /// each one returned.
    ///
    /// - Parameter arguments: the token to wait for, and the bound.
    /// - Returns: the rendered report — one object for a named token, an array
    ///   of them when waiting for everything.
    /// - Throws: nothing. A session-less call and an unknown token are both
    ///   reported in band, because both are states a model can act on.
    public func call(arguments: WaitArguments) async throws -> String {
        await Self.trace.span(
            "WaitTool.call",
            detail: "completionToken=\(arguments.completionToken ?? CallTrace.absent) "
                + "timeout=\(arguments.timeout.map { "\($0)" } ?? CallTrace.absent)"
        ) {
            guard let context = ToolContext.current else {
                return Self.rendered(.object([
                    "result": .string(Self.noSessionResult),
                    "detail": .string(Self.noSessionDetail),
                ]))
            }
            let bound = Self.bounded(arguments.timeout)
            if let token = arguments.completionToken {
                return Self.rendered(.object(
                    await Self.settlement(of: token, in: context, within: bound)
                ))
            }
            let pending = await context.backgroundRuns().map(\.completionToken)
            guard !pending.isEmpty else {
                return Self.rendered(.object([
                    "result": .string(Self.nothingPendingResult),
                    "detail": .string(Self.nothingPendingDetail),
                ]))
            }
            var reports: [InterpreterValue] = []
            for token in pending {
                reports.append(.object(await Self.settlement(of: token, in: context, within: bound)))
            }
            return Self.rendered(.array(reports))
        }
    }

    /// One run's report, in the same shape the sandbox globals report.
    ///
    /// Routed through `MultiTool`'s own builders rather than a second set, so a
    /// finished run reads identically however it was collected.
    ///
    /// - Parameters:
    ///   - token: the run's completion token.
    ///   - context: the session context the run is read through.
    ///   - seconds: the bound to wait within.
    /// - Returns: the report's fields.
    private static func settlement(
        of token: String,
        in context: ToolContext,
        within seconds: Double
    ) async -> [String: InterpreterValue] {
        switch await context.wait(completionToken: token, seconds: seconds) {
        case .settled(let terminal):
            var fields = MultiTool.terminalEventFields(of: terminal)
            fields[finishedRunDirectiveField] = .string(finishedRunDirective)
            return fields
        case .deadlineElapsed:
            return MultiTool.tokenOnlyFields(result: CallResult.timeout, token: token)
        case .unknownToken:
            return MultiTool.tokenOnlyFields(result: CallResult.unknown, token: token)
        }
    }

    /// The field a finished run's report carries ``finishedRunDirective``
    /// under.
    ///
    /// Added here rather than in `MultiTool.terminalEventFields(of:)`,
    /// which the sandbox globals share: a snippet reading `status()` or
    /// `wait()` mid-run is not about to answer anyone, so the directive would
    /// be text inside JavaScript with no reader. This tool's report is read by
    /// the model itself.
    static let finishedRunDirectiveField = "next"

    /// What a finished run's report tells the model to do with the `detail`
    /// beside it.
    ///
    /// **Why the finished case, and why only it.** The two reports this tool
    /// makes when there is nothing to collect already say what to do next —
    /// ``noSessionDetail`` and ``nothingPendingDetail`` each point at the
    /// values already in hand. The finished run's report was the one that
    /// delivered a result and said nothing about it, and that is the moment a
    /// recorded run collected the manifest code it had asked for and then
    /// answered "as soon as the manifest code comes back to me, I'll give it to
    /// you" — three `wait` calls spent, nothing left going, and the value in
    /// hand (task `wnfzwxg`). A report that carries no result carries no
    /// directive either, because telling a model to answer with nothing is
    /// worse than silence.
    ///
    /// This is the only place the text is written, on `RepairDirective
    /// .closingLine`'s terms: the test target reads it here through
    /// `@testable import` rather than restating it, so a reword reaches the
    /// expectation that it is present and the one that it is absent alike.
    static let finishedRunDirective = "The detail above is the result you waited for. Answer with it "
        + "now. Never reply that it will arrive later."

    /// The bound used when the call names none: no bound at all.
    ///
    /// **`wait` blocks until the token finishes, or until a timeout the caller
    /// passed.** Those are the only two ways it returns, so a caller that passes
    /// nothing gets the first one. A host-side cap here would be a third way —
    /// the tool giving up on its own schedule — and it would report a timeout
    /// for work that is still running, sending the model back around a loop it
    /// had already decided to stop for.
    ///
    /// `ToolContext.deadlineSecondsCeiling`, not `.infinity`: the host clamps
    /// every seconds-valued deadline at that ceiling anyway, so naming it here
    /// is the same bound it already treats as unbounded rather than a second
    /// notion of it.
    static let unboundedSeconds: TimeInterval = ToolContext.deadlineSecondsCeiling

    /// The seconds to wait, given what the call asked for.
    ///
    /// The caller's timeout is honoured as passed — it is the bound the model
    /// chose when it decided to block, and nothing here second-guesses it. Only
    /// an absent or non-positive request falls back to waiting for the run to
    /// finish.
    ///
    /// - Parameter requested: the seconds the call asked for, or `nil`.
    /// - Returns: the seconds to wait within.
    static func bounded(_ requested: Double?) -> Double {
        guard let requested, requested > 0 else { return unboundedSeconds }
        return requested
    }

    /// The `result` a session-less call reports.
    static let noSessionResult = "noSession"

    /// What a session-less call says, phrased as something to do next.
    static let noSessionDetail = "This run has no session, so there is nothing running to wait for. "
        + "Answer from the values your tool calls already returned."

    /// The `result` reported when the session has no run still going.
    static let nothingPendingResult = "nothingPending"

    /// What a call with nothing to wait for says, phrased as something to do
    /// next.
    ///
    /// A model that called `wait` believed it was missing a result. Being told
    /// only "nothing is pending" would leave it waiting again; being told the
    /// results are already in hand points it at the answer.
    static let nothingPendingDetail = "No call is still running, so every result you asked for has "
        + "already come back. Answer from what those calls returned."
}

extension WaitTool {
    /// Renders one report the way every other `MultiTool` output is rendered.
    ///
    /// Through `ResultRenderer` rather than an ad-hoc JSON encode, so a `wait`
    /// report is capped and shaped exactly as a `runCode` return value is and a
    /// model reads one format for both.
    ///
    /// - Parameter value: the report to render.
    /// - Returns: the tool's output text.
    static func rendered(_ value: InterpreterValue) -> String {
        ResultRenderer.render(InterpreterResult(returnValue: value, consoleLines: []))
    }
}
