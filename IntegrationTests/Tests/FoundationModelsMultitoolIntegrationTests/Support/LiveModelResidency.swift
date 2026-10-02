import FoundationModelsExtras
import FoundationModelsRouter

/// Keeps one hold of each model that a fixture of this test process
/// resolved, so that each model loads one time for each test process.
///
/// Each scenario resolves its profile through a new `Router`, and that gives
/// each scenario its own recordings directory. A router takes its models from
/// `ModelPool.shared`. The pool loads a model one time and gives a hold of the
/// resident model to each later user, and `Router.resolve` then puts the slot
/// in `ready` with no load. The pool evicts a model when its last hold goes.
/// Without this keeper, the last hold went when a fixture tore down, and the
/// next scenario loaded the same model again.
///
/// The keeper holds the models until the process ends. Thus every model that
/// the suite names stays resident together, and Router prices each later
/// resolve against the footprint of all of them. `ModelResidencyTests` holds
/// the behavior.
actor LiveModelResidency {

    /// The keeper of this test process.
    static let shared = LiveModelResidency()

    /// One hold of each kept model, by its pool key.
    private var holds: [ModelPoolKey: ModelHold] = [:]

    /// Takes one hold of each model in `keys` that this keeper does not hold
    /// yet.
    ///
    /// Call it while the resolved profile still holds its models. The pool
    /// then gives each hold at once, and loads nothing.
    ///
    /// - Parameter keys: the pool key of each model to keep resident.
    /// - Throws: what `ModelPool.acquire(_:)` throws.
    func keep(_ keys: [ModelPoolKey]) async throws {
        for key in keys where holds[key] == nil {
            holds[key] = try await ModelPool.shared.acquire(key)
        }
    }

    /// The pool key of each slot of `profile`: the two generation models and
    /// the embedding model.
    ///
    /// - Parameter profile: the resolved profile.
    /// - Returns: one key for each slot, in the order standard, flash,
    ///   embedding.
    static func poolKeys(of profile: LanguageModelProfile) -> [ModelPoolKey] {
        [
            ModelPoolKey(ref: profile.standard.chosen, role: ModelSlot.standard.poolRole),
            ModelPoolKey(ref: profile.flash.chosen, role: ModelSlot.flash.poolRole),
            ModelPoolKey(ref: profile.embedding.chosen, role: ModelSlot.embedding.poolRole),
        ]
    }
}
