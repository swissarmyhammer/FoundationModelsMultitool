import Synchronization

/// The moment the code of one `runCode` snippet ended: its body returned a
/// value or threw.
///
/// **Why the moment is not the end of the run.** The interpreter gives no
/// result while a bridge promise is pending, also for a `tools.*` call that
/// the snippet did not await (eventplan.md "Async JavaScript":
/// settle-before-return). Each inner call runs to completion (see
/// `RunToCompletionInnerTool`), so the run ends only when the last call ends.
/// A call that is still running when the snippet code ends is a call that
/// the snippet did not await, and its value cannot reach the value that the
/// snippet returns. ``PendingInnerCalls`` names each such call (task
/// `^6nnykct`).
///
/// `MultiTool` sets the mark from a small wrapper around the snippet code
/// (see `MultiTool.wrappingSnippet(_:after:)`). The wrapper calls a host
/// function when the body of the snippet settles.
///
/// A reference type, because the host function that sets the mark and the
/// `tools.*` bindings that read it run in different tasks, and all of them
/// must see the one flag. The flag is atomic, because the interpreter starts
/// those tasks on any thread.
final class SnippetEndMark: Sendable {
    /// Whether the code of the snippet ended.
    private let ended = Atomic<Bool>(false)

    /// Creates a mark for a snippet whose code did not end yet.
    init() {}

    /// Whether the code of the snippet ended.
    var hasEnded: Bool {
        ended.load(ordering: .acquiring)
    }

    /// Records that the code of the snippet ended.
    func markEnded() {
        ended.store(true, ordering: .releasing)
    }
}
