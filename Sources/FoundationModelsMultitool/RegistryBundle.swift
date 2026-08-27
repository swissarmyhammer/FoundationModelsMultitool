// `MultiTool.RegistryBundle` — everything a `runCode` run derives from one
// `Registry`, built in one function so a swap replaces all of it at once.
//
// eventplan.md § "Consolidation of the siblings": "Then MultiTool swaps it in
// atomically at the next turn boundary." Before the swap existed, `MultiTool`
// held the registry and the four values precomputed from it as separate
// `let`s set in `init`. A swap that replaced them one at a time could let a
// run see a preamble from one registry and live tools from another. One
// value, built by one initializer, is what makes the swap atomic.

import FoundationModelsMetadataRegistry

extension MultiTool {
    /// How a bundle builds the searcher `searchTools` reads over its entries.
    enum DiscoverySearch: Sendable {
        /// No `searchTools` reads this bundle, so no discovery searcher is
        /// built. The bundle of a `MultiTool` made with `init(registry:)`.
        case none

        /// A discovery searcher over the entries, in `.auto` mode, with
        /// `selection` as its selection tier — or retrieval alone when
        /// `selection` is `nil`. The bundle `makeSessionToolsAndStaging`
        /// builds.
        case configured(selection: SelectionConfig?)
    }

    /// The shape every bundle of one holder is built in: what does not
    /// change across a swap, so ``RegistryHolder/applyStaged()`` can build
    /// the next bundle exactly as the first one was built.
    struct RegistryBundleShape: Sendable {
        /// Whether the preamble binds `tools.searchTools` — `true` when the
        /// `MultiTool` mounts a discovery tool, `false` otherwise.
        let bindsSearchTools: Bool

        /// How the bundle builds its discovery searcher.
        let discovery: DiscoverySearch
    }

    /// The catalog, the live tools, and every value `runCode` precomputes
    /// from them, as one value.
    ///
    /// A run reads the current bundle one time at its start and keeps it to
    /// its end. A swap replaces the whole bundle in the holder, and never a
    /// field of it, so nothing a run holds changes below it.
    struct RegistryBundle: Sendable {
        /// The catalog + live tool instances this bundle dispatches into.
        let registry: Registry

        /// `help()`/`docs()`'s `HostFunction` bridges — the surface-reading
        /// synchronous globals a run installs. Built one time here, and
        /// re-installed fresh into every `runCode` call's own sandbox by
        /// `Interpreter.run` — installing them is cheap.
        let hostFunctions: [HostFunction]

        /// Every registry entry that has a live tool to dispatch to, paired
        /// with the flat host-function name its `tools.*` binding installs
        /// under. The `AsyncHostFunction`s built from it are not precomputed:
        /// each one closes over the invocation's own `RunBinding`.
        let liveTools: [LiveTool]

        /// The `tools.*` assignment glue prepended to every snippet.
        let preamble: String

        /// The catalog ranker `UnknownToolHint` resolves an invented `tools.*`
        /// name against when no real path resembles its spelling. In
        /// `.retrieval` mode: no selection tier and no embedder, so repairing
        /// a wrong guess costs no model call and no tokens.
        let hintSearcher: MetadataSearcher<APISurface.Entry>

        /// The searcher `searchTools` forwards every call to, or `nil` when
        /// ``shape``'s discovery is `.none`.
        let discoverySearcher: MetadataSearcher<APISurface.Entry>?

        /// The shape this bundle was built in, kept so the next bundle of the
        /// same holder is built the same way.
        let shape: RegistryBundleShape

        /// Builds every value a run needs from `registry`, in `shape`.
        ///
        /// - Parameters:
        ///   - registry: the catalog + live tool instances to expose as
        ///     `tools.*`.
        ///   - shape: what the bundle binds and which searchers it builds.
        init(registry: Registry, shape: RegistryBundleShape) {
            self.registry = registry
            self.shape = shape
            self.hostFunctions = MultiTool.makeHelpDocsHostFunctions(for: registry)
            self.liveTools = MultiTool.makeLiveTools(for: registry)
            self.preamble = MultiTool.makePreamble(for: registry, bindsSearchTools: shape.bindsSearchTools)
            self.hintSearcher = MetadataSearcher(items: registry.surface.entries, mode: .retrieval)
            switch shape.discovery {
            case .none:
                self.discoverySearcher = nil
            case .configured(let selection):
                self.discoverySearcher = SearchToolsTool.makeSearcher(
                    over: registry.surface.entries, selection: selection)
            }
        }
    }
}
