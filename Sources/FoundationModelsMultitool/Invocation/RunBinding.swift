import Foundation
import FoundationModels
import FoundationModelsExtras

/// Everything one `runCode` invocation's inner `tools.*` calls need to reach
/// the session that issued it — captured once, at the top of
/// `MultiTool.call(arguments:)`, from the ambient `ToolContext` the session's
/// own invoker bound around that call.
///
/// ## Why a captured value, and not the ambient context
///
/// The JS thread is not a Swift task (eventplan.md "Async JavaScript":
/// "Session affinity across the seam"). A JSC callback lands outside every
/// task tree, so the `Task` the interpreter's promise pump starts for a
/// `tools.*` call inherits *nothing* — reading `ToolContext.current` from
/// inside that `Task` yields `nil`. The route therefore never depends on
/// task-local inheritance across the seam: it depends on this value, captured
/// while the ambient context is still bound and closed over by every one of
/// the invocation's `AsyncHostFunction`s.
///
/// Two sessions sharing one `MultiTool.Registry` can never cross-route for
/// exactly that reason — each invocation captured its own binding, and no
/// inner call ever consults an ambient value it might have inherited from
/// somewhere else.
///
/// ## What it holds
///
/// The captured ``context`` carries the whole session scope the engine needs:
/// the session identity, the run plane reference, the upstream sink, and the
/// outer run's own `completionToken` (`context.completionToken`) — the
/// correlation the enclosing `runCode` operation posts under. Nothing is
/// copied back out of it, so the binding can never disagree with the context
/// it was captured from.
///
/// Settlement needs no executor of its own here: `JSCInterpreter`'s promise
/// registry already keys every bridge-created promise by id and resolves it
/// in a settle job on the run's own job queue (the "JS thread"), so the
/// interpreter that created a promise is always the one that settles it.
///
/// ## What it does
///
/// ``invoke(_:arguments:journalOp:)`` mounts each inner call on the shared
/// engine as a `RunToCompletionRunner` — "two mounts, one engine, two
/// policies." An inner call runs to completion, bounded by the clock of the
/// outer `runCode` call. That holds also for a tool that declares the
/// background, for example `tools.shell.execute`: `RunToCompletionInnerTool`
/// keeps it out of the background, so a snippet that awaits the call gets
/// its real result and never a pending object (task `^6nnykct`). The engine
/// still owns correlation, events, and outcomes for inner calls: it mints
/// each one a fresh `completionToken` and re-binds `ToolContext.$current`
/// explicitly around it, which is what lets two parallel calls under a snippet's
/// `Promise.all` correlate independently while posting to the run plane and
/// the sink of the one session.
struct RunBinding: Sendable {
    /// The code-mode mount: run to completion, with no clock. Inner
    /// `tools.*` calls run to completion — the constraint boundary
    /// (eventplan.md "The constraint boundary, and the escape hatch"): a
    /// snippet never receives a pending envelope in place of a value it
    /// awaited. A tool that declares the background for itself does not
    /// change this: `RunToCompletionInnerTool` keeps the mode of its mount at
    /// `.runToCompletion`.
    ///
    /// The mount states no clock. Each call path has one outer, tool-level
    /// timeout, and for an inner call that is the clock of the enclosing
    /// `runCode` call (`MultiTool.timeout(from:)`). When that clock ends the
    /// outer run, the cancellation of the run reaches each inner call in
    /// flight through `InFlightInnerCalls`. A clock here would be a second
    /// clock under the outer one: with a host limit of more than its value,
    /// it would cut an inner call that the outer clock still allows.
    static let innerCallMount = ToolMount(mode: .runToCompletion)

    /// The ambient context captured at the top of the enclosing `runCode`
    /// invocation — its session identity, run plane, upstream sink, the outer
    /// run's `completionToken`, and the settle period of each background call
    /// that a tool mounts on this context from inside an inner call.
    let context: ToolContext

    /// The mount policy every inner `tools.*` call is wrapped with. Always a
    /// run-to-completion mode; the clocks are exposed so a caller (and this
    /// package's own tests) can bound an inner call differently without
    /// changing the policy.
    let innerMount: ToolMount

    /// The binding for the enclosing `runCode` invocation, or `nil` when no
    /// session bound an ambient context around it — a `MultiTool`
    /// constructed and called directly, outside any session, has no run
    /// plane at all, and its inner calls run exactly as they did before this
    /// route existed.
    ///
    /// Read this only while the ambient binding is still in scope: at the
    /// top of `MultiTool.call(arguments:)`, never from inside a `tools.*`
    /// call's own `Task`.
    ///
    /// - Parameter grace: The settle period, in seconds, of each background
    ///   call that a tool mounts on the context from inside an inner call:
    ///   `MultiToolConfiguration.inlineSettleGrace` of the enclosing
    ///   `runCode`. The inner `tools.*` call itself runs to completion (see
    ///   `RunToCompletionInnerTool`).
    /// - Returns: The binding, or `nil` outside a session.
    static func ambient(settlingWithin grace: TimeInterval) -> RunBinding? {
        ToolContext.current.map { RunBinding(context: $0.settling(within: grace)) }
    }

    /// Creates a binding over a captured ambient context.
    ///
    /// - Parameters:
    ///   - context: the ambient context captured from the enclosing
    ///     `runCode` invocation.
    ///   - innerMount: the mount policy for inner `tools.*` calls.
    ///     Defaults to ``innerCallMount``.
    init(context: ToolContext, innerMount: ToolMount = RunBinding.innerCallMount) {
        self.context = context
        self.innerMount = innerMount
    }

    /// Runs one inner `tools.*` call through the shared engine, to
    /// completion.
    ///
    /// `ToolContext.mount(_:op:as:)` picks the decorator: a run-to-completion
    /// runner for a `String`-output tool, a context-binding tool for any other
    /// output. The tool goes in through `RunToCompletionInnerTool`, so a tool
    /// that declares the background also gets the run-to-completion runner.
    /// Each mints the call its own `completionToken` and binds
    /// `ToolContext.$current` around it explicitly, so neither depends on what
    /// the calling task did or did not inherit — the property that makes this
    /// safe to call from the JS seam. Every decorator preserves the wrapped
    /// tool's own `Output` type, so the returned value is the tool's,
    /// unchanged, and the mount states that in its return type.
    ///
    /// The mount also supplies the upstream sink. It forwards each event
    /// through this ``context``, and `ToolContext.post(_:)` re-stamps what it
    /// forwards with its own identity. Thus an inner run's events reach the
    /// session's outbox on the **outer** `runCode` run's correlation — the
    /// operation the session actually issued — while the inner run's own
    /// `completionToken` stays with the background runs. A context whose
    /// session has gone away posts into a no-op, which is not an error.
    ///
    /// The `tools.dispatch` span of this call is open around it: the caller,
    /// `MultiTool.invokeAsync`, opens it for both mounts (see
    /// `MultitoolTelemetry.SpanName.toolsDispatch`).
    ///
    /// This is the one place in this package that hands the engine a journal
    /// op, which is why `journalOp` is threaded down to here rather than read
    /// from anything the tool itself carries — a verb does not know its own
    /// noun. See `APISurface.Entry.journalOp` for the derivation and for the
    /// plane the pair appears on.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to. May be passed as a
    ///     concrete `T` or as an `any Tool` existential — SE-0352 implicit
    ///     opening binds `T` to the underlying type either way, exactly as
    ///     `ToolInvoker.invoke(_:content:)` relies on.
    ///   - arguments: the call's already-validated, already-decoded
    ///     arguments.
    ///   - journalOp: the `"verb noun"` string this call's run journals as its
    ///     `op`, or `nil` for a tool registered under no noun — which keeps the
    ///     engine's own default of stamping `op` with the tool's name.
    /// - Returns: the tool's `Output`, exactly as `tool.call(arguments:)`
    ///   produced it.
    /// - Throws: whatever the wrapped tool throws, unchanged; or
    ///   `ToolMountError.timedOut(tool:timeoutSeconds:)` when an injected
    ///   ``innerMount`` states a `timeout` and that timeout ends the call.
    ///   ``innerCallMount`` states none.
    func invoke<T: Tool>(
        _ tool: T, arguments: T.Arguments, journalOp: String? = nil
    ) async throws -> T.Output {
        let engine = context.mount(RunToCompletionInnerTool(wrapped: tool), op: journalOp, as: innerMount)
        return try await engine.call(arguments: arguments)
    }
}

/// A tool that keeps the tool beneath it out of the background, so that an
/// inner `tools.*` call always runs to completion.
///
/// **Why the wrapper is necessary.** `ToolMounting.makeWrapped` of
/// FoundationModelsExtras lets the mount that a tool declares through
/// `BackgroundTool` win over the mount of the call site. `Execute` declares
/// the background, so an inner `tools.shell.execute` call went to the
/// background after the settle period, and the snippet got a pending object
/// in place of the value it awaited. The snippet then continued as if the
/// command had ended. In the SWE-bench run `pending-inner-1012` (instance
/// `django__django-13964`), a snippet deleted the log of a 375-second test
/// run about 5 seconds after the run started, and its grep found no file
/// (task `^6nnykct`).
///
/// This wrapper declares the same mount as the tool beneath it, with the
/// mode changed to `.runToCompletion`. The timeout of the declared mount, and
/// the timeout that the tool gives for one call, stay. The settle period
/// applies only to the outer `runCode` call: a snippet that runs longer than
/// that period goes to the background as one run.
struct RunToCompletionInnerTool<Wrapped: Tool>: Tool, BackgroundTool {
    /// The tool beneath this wrapper.
    let wrapped: Wrapped

    /// The name of the tool beneath.
    var name: String { wrapped.name }

    /// The description of the tool beneath.
    var description: String { wrapped.description }

    /// The argument schema of the tool beneath.
    var parameters: GenerationSchema { wrapped.parameters }

    /// Whether the schema of the tool beneath goes into the instructions.
    var includesSchemaInInstructions: Bool { wrapped.includesSchemaInInstructions }

    /// The mount that the tool beneath declares, run to completion, or `nil`
    /// when it declares none.
    var mount: ToolMount? {
        declared?.mount.map(Self.runningToCompletion)
    }

    /// The mount that the tool beneath gives for one call, run to
    /// completion, or `nil` when it gives none.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The mount of the call.
    func mount(for arguments: GeneratedContent) -> ToolMount? {
        declared?.mount(for: arguments).map(Self.runningToCompletion)
    }

    /// The timeout that the tool beneath gives for one call.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The timeout in seconds, or `nil` for the timeout of the
    ///   mount.
    func timeout(from arguments: GeneratedContent) -> TimeInterval? {
        declared?.timeout(from: arguments)
    }

    /// Calls the tool beneath.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: What the tool beneath returns, unchanged.
    /// - Throws: What the tool beneath throws, unchanged.
    func call(arguments: Wrapped.Arguments) async throws -> Wrapped.Output {
        try await wrapped.call(arguments: arguments)
    }

    /// The tool beneath as a `BackgroundTool`, or `nil`.
    private var declared: (any BackgroundTool)? {
        wrapped as? any BackgroundTool
    }

    /// `mount` with the mode `.runToCompletion` and the same timeout.
    ///
    /// - Parameter mount: A mount that a tool declares.
    /// - Returns: The changed mount.
    private static func runningToCompletion(_ mount: ToolMount) -> ToolMount {
        ToolMount(mode: .runToCompletion, timeout: mount.timeout)
    }
}
