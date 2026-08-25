import Foundation
import FoundationModels
import FoundationModelsRouter

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
/// the session identity, the mailbox reference, the upstream sink, and the
/// outer run's own `completionToken` (`context.completionToken`) — the
/// correlation the enclosing `runCode` operation posts under. Nothing is
/// copied back out of it, so the binding can never disagree with the context
/// it was captured from.
///
/// Settlement needs no executor of its own here: `JSCInterpreter`'s promise
/// registry already keys every bridge-created promise by id and resolves it
/// from the run's own dedicated worker queue (the "JS thread") in
/// `pumpUntilSettled`, so the interpreter that created a promise is always
/// the one that settles it.
///
/// ## What it does
///
/// ``invoke(_:arguments:journalOp:)`` mounts each inner call on the shared
/// `DetachingTool` engine with elevation **off** — eventplan.md "Elevation":
/// "two mounts, one engine, two policies." Only the outer `runCode` call
/// elevates; an inner call runs to completion, bounded by its `timeout`. The
/// engine still owns correlation, events, and outcomes for inner calls: it
/// mints each one a fresh `completionToken` and re-binds
/// `ToolContext.$current` explicitly around it, which is what lets two
/// parallel calls under a snippet's `Promise.all` correlate independently
/// while posting to the one session's mailbox and sink.
struct RunBinding: Sendable {
    /// The code-mode mount: elevation off, stock clocks. Inner `tools.*`
    /// calls run to completion, bounded only by the engine's per-call
    /// `timeout` — the constraint boundary (eventplan.md "The constraint
    /// boundary, and the escape hatch"): a snippet never receives a pending
    /// envelope in place of a value it awaited.
    static let innerCallMount = DetachConfiguration(mode: .runToCompletion)

    /// Where each inner `tools.*` dispatch is recorded — see ``CallTrace``.
    ///
    /// This is the one place an inner call is visible as itself. Below it the
    /// call is inside the shared engine, and above it the call is inside a JSC
    /// promise the interpreter is pumping — so a snippet whose `await` never
    /// settles looks, from either side, like a snippet that has not finished.
    /// One `tools.*` call under `Promise.all` that never comes back is
    /// otherwise indistinguishable from all of them being slow.
    static let trace = CallTrace(category: "RunBinding")

    /// The ambient context captured at the top of the enclosing `runCode`
    /// invocation — its session identity, mailbox, upstream sink, and the
    /// outer run's `completionToken`.
    let context: ToolContext

    /// The mount policy every inner `tools.*` call is wrapped with. Always
    /// an elevation-off mode; the clocks are exposed so a caller (and this
    /// package's own tests) can bound an inner call differently without
    /// changing the policy.
    let innerElevation: DetachConfiguration

    /// The binding for the enclosing `runCode` invocation, or `nil` when no
    /// session bound an ambient context around it — a `MultiTool`
    /// constructed and called directly, outside any session, has no run
    /// plane at all, and its inner calls run exactly as they did before this
    /// route existed.
    ///
    /// Read this only while the ambient binding is still in scope: at the
    /// top of `MultiTool.call(arguments:)`, never from inside a `tools.*`
    /// call's own `Task`.
    static var ambient: RunBinding? {
        ToolContext.current.map { RunBinding(context: $0) }
    }

    /// Creates a binding over a captured ambient context.
    ///
    /// - Parameters:
    ///   - context: the ambient context captured from the enclosing
    ///     `runCode` invocation.
    ///   - innerElevation: the mount policy for inner `tools.*` calls.
    ///     Defaults to ``innerCallMount``.
    init(context: ToolContext, innerElevation: DetachConfiguration = RunBinding.innerCallMount) {
        self.context = context
        self.innerElevation = innerElevation
    }

    /// Runs one inner `tools.*` call through the shared elevation engine with
    /// elevation off.
    ///
    /// `ToolDetachment.wrapping(tool:inheriting:sink:op:configuration:)`
    /// picks the decorator: `DetachingTool` for a `String`-output tool,
    /// `ContextBindingTool` for any other output. Both mint the call its own
    /// `completionToken` and bind `ToolContext.$current` around it
    /// explicitly, so neither depends on what the calling task did or did not
    /// inherit — the property that makes this safe to call from the JS seam.
    /// Either decorator preserves the wrapped tool's own `Output` type, so
    /// the returned value is the tool's, unchanged.
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
    ///   `DetachingToolError.timedOut(tool:timeoutSeconds:)` when the mount's
    ///   per-call `timeout` ends the call.
    func invoke<T: Tool>(
        _ tool: T, arguments: T.Arguments, journalOp: String? = nil
    ) async throws -> T.Output {
        try await Self.trace.span(
            "RunBinding.invoke",
            detail: "tool=\(tool.name) outerToken=\(context.completionToken)"
        ) {
            let mounted = ToolDetachment.wrapping(
                tool: tool,
                inheriting: context,
                sink: AmbientUpstreamSink(context: context),
                op: journalOp,
                configuration: innerElevation
            )
            guard let engine = mounted as? any Tool<T.Arguments, T.Output> else {
                // Unreachable: both decorators preserve `Arguments`/`Output`, and
                // `ToolDetachment.wrapping`'s own unreachable fallback returns the
                // tool itself, which matches too. Kept as a graceful degradation
                // rather than a trap, matching this package's "throw/degrade,
                // never trap" posture — the call still happens, only without the
                // engine's correlation.
                return try await tool.call(arguments: arguments)
            }
            return try await engine.call(arguments: arguments)
        }
    }
}

/// The upstream end of an inner `tools.*` run's event route: the sink
/// `RunBinding` hands the engine, forwarding every event the run's funnel
/// produces through the ambient `ToolContext` the enclosing `runCode` call was
/// bound to.
///
/// `ToolContext.post(_:)` is the only egress a captured context publishes, and
/// it re-stamps what it forwards with its own identity. So an inner run's
/// events reach the session's outbox on the **outer** `runCode` run's
/// correlation — which is the operation the session actually issued — while
/// the inner run's own `completionToken` stays with the background runs: the engine's
/// funnel addresses the session mailbox by it, and the inner tool reads it
/// from its own `ToolContext.current`.
///
/// A context that is bound but whose session has gone away posts into a
/// no-op, exactly as a `nil` ambient context does — neither is an error.
struct AmbientUpstreamSink: OperationEventSink {
    /// The captured ambient context every event is forwarded through.
    let context: ToolContext

    func post(event: OperationEvent) async {
        await context.post(event)
    }
}
