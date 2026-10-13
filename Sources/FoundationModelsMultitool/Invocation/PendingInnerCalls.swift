import Synchronization

/// The name of one inner `tools.*` binding, as a notice of
/// ``PendingInnerCalls`` states it.
struct InnerCallName: Sendable {
    /// The path a snippet calls the binding by, without the `tools.` prefix:
    /// for example `"shell.execute"`.
    let path: String

    /// The `Tool` name of the wrapped tool: for example `"execute"`.
    let tool: String

    /// The `op` the run of the call journals: the `"verb noun"` pair of a
    /// grouped tool (for example `"execute shell"`), or the tool name.
    let op: String

    /// The field of the value of the call that identifies its run, or `nil`
    /// when the tool gives no such field. For `tools.shell.execute` it is
    /// `commandID`: the output of the command stays in the shell store under
    /// that identifier.
    let identifierField: String?
}

/// The inner `tools.*` calls of one `runCode` invocation that were still
/// running when the snippet code ended, and the notice that names them.
///
/// **The gap this closes.** A snippet can start a call and not await it.
/// Each inner call runs to completion, and the interpreter gives no result
/// before the last call ends (see ``SnippetEndMark``). But the code of the
/// snippet ended before the call ended, so the value of the call is not in
/// the value that the snippet returned. Without a notice, the result hides
/// that call from the model. In SWE-bench run `noop-stop-1012` (instance
/// `django__django-13447`), a snippet started a test command, returned only a
/// grep result, and ended. The model then thought that the command failed,
/// and it ran the same command again (task `^qg52whq`).
///
/// So each inner call that ends after the snippet code ended is recorded
/// here, and the result of the run names each one (task `^6nnykct`). A call
/// that the snippet awaited always ends before the snippet code ends, so it
/// is never named. A nested `tools.runCode` run records its inner calls into
/// the record of the run the model started, because a snippet reads the
/// nested result as a value, and only the outer result reaches the model
/// (see `MultiTool.EnclosingRun`).
///
/// The notice does not tell the model that a call continues in the
/// background: the result waited for each call to end. The rendered result
/// is the inline answer and also the mail of a background run, so one
/// notice serves both.
///
/// A reference type guarded by a `Mutex`, rather than an `actor`, for the
/// reason of ``ToolReturnLedger``: the recording side runs inside
/// `AsyncHostFunction` bodies that the promise pump of the interpreter starts
/// on any thread, and each operation is a small synchronous step.
final class PendingInnerCalls: Sendable {
    /// One inner call that ended after the snippet code ended.
    private struct UnawaitedCall: Sendable {
        /// The name of the binding that was called.
        let name: InnerCallName

        /// The identifier of the run of the call, as `field "value"`, or
        /// `nil` when the call gave none.
        let identifier: String?

        /// This call as one line of the notice.
        var line: String {
            let named = "- tools.\(name.path): tool \"\(name.tool)\", op \"\(name.op)\""
            return identifier.map { "\(named), \($0)" } ?? named
        }
    }

    /// The first sentence of the notice, ahead of the list of calls.
    static let noticeLead =
        "This snippet ended before these tools.* calls that it started ended. The result waited for each "
        + "call to end, but the value that the snippet returned does not hold their results:"

    /// The sentence after the list of calls.
    static let noticeAction = "Do not run these calls again."

    /// Each recorded call, in the order the calls ended.
    private let calls = Mutex<[UnawaitedCall]>([])

    /// Creates an empty record.
    init() {}

    /// Records one call that ended after the snippet code ended.
    ///
    /// - Parameters:
    ///   - name: The name of the binding that was called.
    ///   - value: The value that the call gave.
    func note(_ name: InnerCallName, gave value: InterpreterValue) {
        let call = UnawaitedCall(name: name, identifier: Self.identifier(named: name.identifierField, in: value))
        calls.withLock { $0.append(call) }
    }

    /// The notice that names each recorded call, or `nil` when this run
    /// recorded none.
    var notice: String? {
        let unawaited = calls.withLock { $0 }
        guard !unawaited.isEmpty else { return nil }
        return ([Self.noticeLead] + unawaited.map(\.line) + [Self.noticeAction]).joined(separator: "\n")
    }

    /// The identifier of the run of a call, as `field "value"`.
    ///
    /// - Parameters:
    ///   - field: The field that holds the identifier, or `nil` when the tool
    ///     gives none.
    ///   - value: The value that the call gave.
    /// - Returns: The identifier, or `nil` when `value` holds no string in
    ///   `field`.
    private static func identifier(named field: String?, in value: InterpreterValue) -> String? {
        guard let field, case .object(let fields) = value, case .string(let identifier)? = fields[field] else {
            return nil
        }
        return "\(field) \"\(identifier)\""
    }
}
