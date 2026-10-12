import FoundationModelsExtras
import Synchronization

/// The name of one inner `tools.*` binding, as a pending notice states it.
struct InnerCallName: Sendable {
    /// The path a snippet calls the binding by, without the `tools.` prefix:
    /// for example `"shell.execute"`.
    let path: String

    /// The `Tool` name of the wrapped tool: for example `"execute"`.
    let tool: String

    /// The `op` the run of the call journals: the `"verb noun"` pair of a
    /// grouped tool (for example `"execute shell"`), or the tool name.
    let op: String
}

/// The inner `tools.*` calls of one `runCode` invocation that gave the
/// snippet a pending object, and the notice that names them.
///
/// **The gap this closes.** An inner call of a background tool, for example
/// `tools.shell.execute`, gives the snippet a pending object when it runs
/// longer than its settle period. The call continues in the background, and
/// its result comes back to the session as a new message. A snippet that does
/// not return the pending object hides that call from the model. In SWE-bench
/// run `noop-stop-1012` (instance `django__django-13447`), a snippet started a
/// test command, returned only a grep result, and ended. The model then
/// thought that the command failed, and it ran the same command again (task
/// `^qg52whq`).
///
/// So each inner call that gives a pending object is recorded here, and the
/// result of the run names each one. A nested `tools.runCode` run records its
/// inner calls into the record of the run the model started, because a snippet
/// reads the nested result as a value, and only the outer result reaches the
/// model (see `MultiTool.EnclosingRun`). The notice uses the shared
/// `PendingRunEnvelope.pendingWorkInstruction`, the same text that each
/// pending envelope carries. The rendered result is the inline answer and
/// also the mail of a background run, so one notice serves both.
///
/// A reference type guarded by a `Mutex`, rather than an `actor`, for the
/// reason of ``ToolReturnLedger``: the recording side runs inside
/// `AsyncHostFunction` bodies that the promise pump of the interpreter starts
/// on any thread, and each operation is a small synchronous step.
final class PendingInnerCalls: Sendable {
    /// One inner call that gave the snippet a pending object.
    private struct PendingCall: Sendable {
        /// The name of the binding that was called.
        let name: InnerCallName

        /// The field of the pending object that identifies the run:
        /// `commandID` for a shell command, `completionToken` for each
        /// other tool.
        let identifierField: String

        /// The value of that field.
        let identifier: String

        /// This call as one line of the notice.
        var line: String {
            "- tools.\(name.path): tool \"\(name.tool)\", op \"\(name.op)\", \(identifierField) \"\(identifier)\""
        }
    }

    /// The first sentence of the notice, ahead of the list of calls.
    static let noticeLead =
        "This snippet ended, but these tools.* calls that it started did not finish. They continue in "
        + "the background:"

    /// The sentence after the list of calls, ahead of the shared
    /// pending-work text.
    static let noticeAction = "Do not run these calls again."

    /// Each pending call, in the order the calls gave their pending objects.
    private let calls = Mutex<[PendingCall]>([])

    /// Creates an empty record.
    init() {}

    /// Runs one `tools.*` call, and records it when it gives a pending object.
    ///
    /// A pending object that the record holds already is not recorded again.
    /// This occurs when a nested `tools.runCode` returns the pending object of
    /// one of its inner calls: the nested run records that inner call into
    /// this record first, and then the `tools.runCode` call of the outer run
    /// gives the same pending object. The first entry names the call that
    /// started the run, thus the notice keeps it.
    ///
    /// - Parameters:
    ///   - name: The name of the binding.
    ///   - call: The binding to run.
    /// - Returns: What `call` returned, unchanged.
    /// - Throws: Whatever `call` throws, unchanged.
    func noting(
        _ name: InnerCallName, _ call: () async throws -> InterpreterValue
    ) async rethrows -> InterpreterValue {
        let value = try await call()
        if let pending = Self.pendingCall(named: name, in: value) {
            calls.withLock { recorded in
                guard !recorded.contains(where: { $0.identifier == pending.identifier }) else { return }
                recorded.append(pending)
            }
        }
        return value
    }

    /// The notice that names each pending call, or `nil` when no call of this
    /// run gave a pending object.
    var notice: String? {
        let pending = calls.withLock { $0 }
        guard !pending.isEmpty else { return nil }
        let lines = [Self.noticeLead] + pending.map(\.line)
            + ["\(Self.noticeAction) \(PendingRunEnvelope.pendingWorkInstruction)"]
        return lines.joined(separator: "\n")
    }

    /// The pending call that `value` states, or `nil` when `value` is not a
    /// pending object.
    ///
    /// - Parameters:
    ///   - name: The name of the binding that gave `value`.
    ///   - value: The value the binding gave.
    /// - Returns: The pending call.
    private static func pendingCall(named name: InnerCallName, in value: InterpreterValue) -> PendingCall? {
        guard let completionToken = value.pendingCompletionToken else { return nil }
        if case .object(let fields) = value, case .string(let commandID)? = fields[Execute.commandIDField] {
            return PendingCall(name: name, identifierField: Execute.commandIDField, identifier: commandID)
        }
        return PendingCall(
            name: name, identifierField: SnippetPendingField.completionToken, identifier: completionToken)
    }
}
