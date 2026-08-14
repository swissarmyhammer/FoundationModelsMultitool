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
/// **No session, no run plane.** Like the sandbox globals, this reads the
/// ambient `ToolContext`; constructed and called outside any session it reports
/// that there is nothing to wait for rather than trapping, which is the mode
/// every unit suite in this package runs in.
// MARK: - `wait` never parks itself

extension WaitTool: DetachmentParameterProviding {
    /// The per-call clocks a `wait` call carries: neither of them a limit.
    ///
    /// **There are two ways for `wait` to return, and this is what keeps a
    /// third from existing.** It returns when the run settles, or when the
    /// bound the caller passed elapses. Mounted like every other tool, on a
    /// stock `.detaching` configuration, a `wait` call that blocks past the
    /// mount's five seconds would *park itself* — handing the model a
    /// completion token for its own wait, which is the exact regress this tool
    /// was built to end (task `^2w9vbkm`, and `^w8dzvee` D5). It was only
    /// accidentally safe before: safe while the runs it waited on happened to
    /// settle inside the mount's window.
    ///
    /// Both clocks are answered at ``unboundedSeconds`` for the same reason
    /// `SearchToolsTool` answers both of its own that way: a per-call answer
    /// overrides the wrap-time configuration, and neither question has a
    /// bounded answer here. The wait clock asks when this call should become
    /// asynchronous — never, since blocking is the whole point of the call.
    /// The work clock asks how long it may run before being cancelled and
    /// reported failed — no limit, because the caller's own `timeout` is the
    /// only bound in this design, and a host clock firing under it would
    /// report `deadlineElapsed` on its own schedule rather than the caller's.
    ///
    /// This is a workaround, and it should be read as one: what the tool needs
    /// to declare is `DetachConfiguration.Mode.runToCompletion`, which is read
    /// from the wrap-time configuration and which
    /// `DetachmentParameterProviding` cannot express. Filed on Router's
    /// `^w8dzvee`. Two large numbers state the intent that a per-tool mode
    /// would declare.
    ///
    /// - Parameter arguments: the call's arguments as opaque
    ///   `GeneratedContent`. Unread: every `wait` call gets the same answers,
    ///   because the rule is the tool's, not the call's.
    /// - Returns: an unbounded wait clock and an unbounded work clock.
    public func detachmentClocks(
        from arguments: GeneratedContent
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        (Self.unboundedSeconds, Self.unboundedSeconds)
    }
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
        one. Each finished call comes back with its `detail` — that is the result, and it is what to
        answer from. A call still running when the bound passes comes back as
        `\(RunPlaneState.deadlineElapsed)`, which means it is still going and nothing has failed: call
        wait again if you still need it.
        """

    /// Creates the tool.
    public init() {}

    /// Waits for the named run, or for every pending run, and reports what
    /// each one returned.
    ///
    /// - Parameter arguments: the token to wait for, and the bound.
    /// - Returns: the rendered report — one object for a named token, an array
    ///   of them when waiting for everything.
    /// - Throws: nothing. A session-less call and an unknown token are both
    ///   reported in band, because both are states a model can act on.
    public func call(arguments: WaitArguments) async throws -> String {
        guard let context = ToolContext.current else {
            return Self.rendered(.object([
                "state": .string(Self.noRunPlaneState),
                "detail": .string(Self.noRunPlaneDetail),
            ]))
        }
        let bound = Self.bounded(arguments.timeout)
        if let token = arguments.completionToken {
            return Self.rendered(.object(
                await Self.settlement(of: token, in: context, within: bound)
            ))
        }
        let pending = await context.parkedRuns().map(\.completionToken)
        guard !pending.isEmpty else {
            return Self.rendered(.object([
                "state": .string(Self.nothingPendingState),
                "detail": .string(Self.nothingPendingDetail),
            ]))
        }
        var reports: [InterpreterValue] = []
        for token in pending {
            reports.append(.object(await Self.settlement(of: token, in: context, within: bound)))
        }
        return Self.rendered(.array(reports))
    }

    /// One run's settlement, reported in the same shape the run plane reports.
    ///
    /// Routed through `MultiTool`'s own builders rather than a second set, so a
    /// settled run reads identically however it was collected.
    ///
    /// - Parameters:
    ///   - token: the run's completion token.
    ///   - context: the session context the run plane is read through.
    ///   - seconds: the bound to wait within.
    /// - Returns: the report's fields.
    private static func settlement(
        of token: String,
        in context: ToolContext,
        within seconds: Double
    ) async -> [String: InterpreterValue] {
        switch await context.wait(completionToken: token, seconds: seconds) {
        case .settled(let terminal):
            return MultiTool.terminalEventFields(of: terminal, state: RunPlaneState.settled)
        case .deadlineElapsed:
            return MultiTool.tokenOnlyFields(state: RunPlaneState.deadlineElapsed, token: token)
        case .unknownToken:
            return MultiTool.tokenOnlyFields(state: RunPlaneState.unknownToken, token: token)
        }
    }

    /// The bound used when the call names none: no bound at all.
    ///
    /// **`wait` blocks until the token finishes, or until a timeout the caller
    /// passed.** Those are the only two ways it returns, so a caller that passes
    /// nothing gets the first one. A host-side cap here would be a third way —
    /// the tool giving up on its own schedule — and it would report
    /// `deadlineElapsed` for work that is still running, sending the model back
    /// around a loop it had already decided to stop for.
    ///
    /// `ToolContext.waitSecondsCeiling`, not `.infinity`: the run plane clamps
    /// every wait at that ceiling anyway, so naming it here is the same bound
    /// the host already treats as unbounded rather than a second notion of it.
    static let unboundedSeconds: TimeInterval = ToolContext.waitSecondsCeiling

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

    /// The `state` a session-less call reports.
    static let noRunPlaneState = "noRunPlane"

    /// What a session-less call says, phrased as something to do next.
    static let noRunPlaneDetail = "This run has no session, so there is nothing running to wait for. "
        + "Answer from the values your tool calls already returned."

    /// The `state` reported when the session has no pending run at all.
    static let nothingPendingState = "nothingPending"

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
