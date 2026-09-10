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
    /// The weight of a signal ``hintSearchWeights`` keeps whole.
    private static let wholeHintSignalWeight = 1.0

    /// The weight of a signal ``hintSearchWeights`` drops.
    private static let droppedHintSignalWeight = 0.0

    /// The per-signal fusion weights ``RegistryBundle/hintSearcher`` ranks
    /// with: BM25 and cosine whole, and the character-trigram signal dropped.
    ///
    /// **Why this searcher alone drops the trigram signal.** The trigram
    /// signal is a signal of SPELLING: it is the Dice overlap of the
    /// character trigrams of the query with the character trigrams of the
    /// whole rendered block. `UnknownToolHint` already answers a wrong
    /// spelling one tier earlier, with the trigram overlap of the guessed
    /// NAME against the catalog names, and it reaches this searcher only when
    /// that tier rejects the guess. What is left to rank is a guess that
    /// resembles no name — a plain-language intent against nine blocks of
    /// prose — and over that input the trigram signal measures the length of
    /// a block and nothing else.
    ///
    /// **Measured on 2026-09-10, over the nine-entry files-and-shell
    /// surface.** A three-word intent shares its trigrams with every block
    /// that holds the words, so the count of shared trigrams saturates and
    /// `2·|shared| / (|query| + |block|)` falls to the reciprocal of the size
    /// of the block. `shell.execute` renders the largest block of the nine
    /// (703 trigrams) and `shell.getLines` the smallest (480), thus the
    /// trigram list ranked the reader over the runner for every guess that
    /// asks to run a command:
    ///
    ///     intent                 bm25            cosine          trigram
    ///     terminal run command   shell.execute   shell.execute   shell.getLines
    ///     bash run               shell.execute   shell.execute   shell.getLines
    ///     terminal run tests     shell.execute   shell.execute   shell.getLines
    ///
    /// The two signals that read what an entry MEANS both named
    /// `shell.execute` first, and the reciprocal-rank fusion of three lists
    /// still answered `shell.getLines`, because `shell.execute` stood sixth
    /// and ninth on the trigram list. No wording of the descriptions repairs
    /// that: the ranking follows the size of the block. Card `^pwn02m4`
    /// measured it and dropped the signal here.
    ///
    /// **`searchTools` keeps every signal.** That searcher ranks the words a
    /// person really wrote, where a near-spelling of a tool name is evidence
    /// rather than noise, and `SearchToolsTool.makeSearcher(over:selection:
    /// embedder:)` therefore takes the default weights.
    static let hintSearchWeights = Weights(
        bm25: wholeHintSignalWeight,
        trigram: droppedHintSignalWeight,
        cosine: wholeHintSignalWeight)

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

        /// The embedder both searchers of the bundle rank with, or `nil` for
        /// keyword-only ranking. The host's resolved profile carries one, and
        /// `makeSessionToolsAndStaging(librarian:embedder:sampleGenerator:)`
        /// is where the host hands it over.
        let embedder: (any TextEmbedding)?
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
        /// `.retrieval` mode: no selection tier, so repairing a wrong guess
        /// costs no generation. It ranks with ``shape``'s embedder when the
        /// host gave one, which costs one catalog embed at the first hint and
        /// one query embed per hint after it — see
        /// ``SearchToolsTool/makeSearcher(over:selection:embedder:)`` for who
        /// pays that first embed. It ranks with ``MultiTool/hintSearchWeights``
        /// rather than with the default weights, which is where the reason
        /// stands.
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
            self.hintSearcher = MetadataSearcher(
                index: MetadataIndex(items: registry.surface.entries), mode: .retrieval,
                weights: MultiTool.hintSearchWeights, embedder: shape.embedder, selection: nil)
            switch shape.discovery {
            case .none:
                self.discoverySearcher = nil
            case .configured(let selection):
                self.discoverySearcher = SearchToolsTool.makeSearcher(
                    over: registry.surface.entries, selection: selection, embedder: shape.embedder)
            }
        }
    }
}
