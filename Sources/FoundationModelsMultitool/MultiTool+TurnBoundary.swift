import FoundationModelsRouter

// MARK: - The turn boundary (eventplan.md § "Consolidation of the siblings")
//
// "Then MultiTool swaps it in atomically at the next turn boundary — the same
// boundary where the outbox folds in events." Router supplies the boundary
// through `TurnBoundaryTool.turnWillBegin()`: the session calls it one time
// at each turn boundary, after it drains the outbox and before the model call
// of the turn. This file is where `runCode` applies the registry a refresher
// staged.

extension MultiTool {
    /// Stages `registry` as the next surface of this tool, and of every copy
    /// and every `searchTools` that shares its holder. Only the newest staged
    /// registry is kept. It is applied at the next ``turnWillBegin()``.
    ///
    /// Non-mutating: the struct does not change, the box does.
    ///
    /// - Parameter registry: The registry to swap in at the next tick.
    public func stage(_ registry: Registry) {
        holder.stage(registry)
    }
}

extension MultiTool: TurnBoundaryTool {
    /// Applies the staged registry, when there is one, so the next `runCode`
    /// call — and `help()`, `docs()` and the `searchTools` mounted beside it —
    /// read the new surface.
    ///
    /// A run already in flight keeps the bundle it started with: it read the
    /// holder one time at its start (see `RegistryHolder`).
    public func turnWillBegin() async {
        holder.applyStaged()
    }
}
