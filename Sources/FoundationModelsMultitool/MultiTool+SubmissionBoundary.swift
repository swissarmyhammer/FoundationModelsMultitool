import FoundationModelsExtras

// MARK: - The submission boundary (eventplan.md § "Consolidation of the siblings")
//
// "Then MultiTool swaps it in atomically at the next turn boundary — the same
// boundary where the outbox folds in events." The host supplies the boundary
// through `SubmissionBoundaryTool.submissionWillBegin()` of
// FoundationModelsExtras: a Router session calls it one time before each
// submission, after the session takes the waiting messages and before the
// model call of the submission. A continuation of the same answer is a
// submission too, so the hook also runs between two submissions of one
// answer. This file is where `runCode` applies the registry
// a refresher staged.

extension MultiTool {
    /// Stages `registry` as the next surface of this tool, and of every copy
    /// and every `searchTools` that shares its holder. Only the newest staged
    /// registry is kept. It is applied at the next ``submissionWillBegin()``.
    ///
    /// Non-mutating: the struct does not change, the box does.
    ///
    /// - Parameter registry: The registry to swap in at the next tick.
    public func stage(_ registry: Registry) {
        holder.stage(registry)
    }
}

extension MultiTool: SubmissionBoundaryTool {
    /// Applies the staged registry, when there is one, so the next `runCode`
    /// call — and `help()`, `docs()` and the `searchTools` mounted beside it —
    /// read the new surface.
    ///
    /// The host session calls this hook before each submission. A
    /// continuation of the same answer is a submission too, so a registry
    /// staged while an answer runs is applied before the next submission of
    /// that answer.
    ///
    /// A run already in flight keeps the bundle it started with: it read the
    /// holder one time at its start (see `RegistryHolder`).
    public func submissionWillBegin() async {
        holder.applyStaged()
    }
}
