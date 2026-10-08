import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter

/// The discovery seams of `FoundationModelsMultitool`, over the Router
/// handles of a resolved profile.
///
/// Discovery takes plain FoundationModels and FoundationModelsExtras types
/// and knows nothing of Router: a ``SearchToolsTool/SelectionFactory`` whose
/// `SelectionConfig` holds an `any LanguageModel`, an `any PooledEmbedding`,
/// and an `any LanguageModel` for the sample snippet. The host picks the
/// models. This is the one place where this suite turns its Router handles
/// into those seams, and `LiveRouterFixture.discoverySeams` gives the result
/// to each scenario:
///
/// ```swift
/// let embedder = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding)
/// let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: embedder)
/// let mounted = try registry.makeSessionToolsAndStaging(
///     selection: seams.selection, embedder: seams.embedder, sampleModel: seams.sampleModel)
/// ```
///
/// Each seam is a pooled handle of the model that a Router slot chose, from
/// the model pool that the Router resolves into. Thus a seam and its Router
/// slot use one model in memory, and one generation queue.
///
/// It stands in this test target and not in the library: the library does not
/// link Router.
struct RouterDiscoverySeams: Sendable {
    /// Makes the selection tier for the catalog ids, on the model of the
    /// librarian.
    let selection: SearchToolsTool.SelectionFactory

    /// The pooled embedder both searchers rank with. From its first embed
    /// call, it keeps a hold of the embedding model in the model pool of the
    /// process.
    let embedder: any PooledEmbedding

    /// The model the sample snippet is written on, or `nil` when no
    /// generator was given and `searchTools` answers with signatures alone.
    let sampleModel: (any LanguageModel)?

    /// Makes the seams over the Router handles of a resolved profile.
    ///
    /// **The librarian must be a model other than the model of the session
    /// whose turn calls `searchTools`. That is a correctness requirement, not
    /// a cost preference.** `searchTools` is synchronous, so its body runs
    /// inside the open submission of the calling session. The model pool runs
    /// the work of each model in order on one generation queue, and the
    /// pooled model of a slot uses the same queue as the Router slot. A
    /// selection session on a different model waits its turn on the queue of
    /// that model, and the search completes. A session on the same model would
    /// wait for the open submission to end, and that submission ends only when
    /// this tool returns. The queue refuses that wait at once with
    /// `GenerationQueueError.waitInsideOpenSubmission`, and the search gives
    /// that error. What keeps this suite clear of it is that each profile of
    /// this target puts a different model in `flash` than in `standard`, and
    /// `ProfileSlotSeparationTests` holds that.
    ///
    /// - Parameters:
    ///   - librarian: the slot whose model answers every selection prompt.
    ///     This suite passes `profile.flash`.
    ///   - embedder: the pooled embedder both searchers rank with. This suite
    ///     passes the result of ``acquireEmbedder(for:from:)`` for
    ///     `profile.embedding`.
    ///   - sampleGenerator: the slot whose model writes the sample snippet,
    ///     or `nil` (the default) for no sample. It must also be a model
    ///     other than the model of the session that mounts `searchTools`, for
    ///     the same reason as the librarian. Thus the main generation slot,
    ///     which drives that session, is not a correct generator.
    init(librarian: RoutedLLM, embedder: PooledEmbedder, sampleGenerator: RoutedLLM? = nil) {
        let librarianModel = Self.pooledModel(of: librarian)
        self.selection = { _ in SelectionConfig(model: librarianModel) }
        self.embedder = embedder
        self.sampleModel = sampleGenerator.map { Self.pooledModel(of: $0) }
    }

    /// Makes the pooled embedder for the embedding slot of a resolved
    /// profile, by the `ModelRef` that the slot chose.
    ///
    /// The embedder loads nothing when you make it. Its first embed call
    /// acquires the model from `pool`. The Router resolves each profile into
    /// its model pool, and the default pool is `ModelPool.shared`, the pool of
    /// the process. While the profile exists, the Router keeps a hold of the
    /// embedding model, so the model is resident: the pool adds a hold and
    /// loads nothing. Thus the Router embedding slot and the discovery
    /// embedder use one embedding model in memory. When the model is not
    /// resident, the pool loads it with its own loader, the loader of
    /// `ModelPool(loader:)`.
    ///
    /// - Parameters:
    ///   - embedding: the embedding handle of a resolved profile. Its
    ///     `chosen` model is the pool key.
    ///   - pool: the pool to acquire the model from. The default is
    ///     `ModelPool.shared`, the pool that a Router uses when it gets no
    ///     pool.
    /// - Returns: the pooled embedder. After its first embed call, it keeps a
    ///   hold of the model, so the model stays resident while the embedder
    ///   exists. An embed call throws what the load throws, or
    ///   `PooledEmbedderError.notAnEmbedding` when the container of the key
    ///   is not a `PooledEmbedding`.
    static func acquireEmbedder(for embedding: RoutedEmbedder, from pool: ModelPool = .shared) -> PooledEmbedder {
        PooledEmbedder(ref: embedding.chosen, pool: pool)
    }

    /// Makes the pooled model for a generation slot of a resolved profile, by
    /// the `ModelRef` that the slot chose.
    ///
    /// The model loads nothing when you make it. Each session on it acquires
    /// the model from `pool`, as ``acquireEmbedder(for:from:)`` tells for the
    /// embedder: while the profile exists, the model is resident, and the
    /// pool adds a hold and loads nothing.
    ///
    /// - Parameters:
    ///   - slot: the generation handle of a resolved profile. Its `chosen`
    ///     model is the pool key.
    ///   - pool: the pool to acquire the model from. The default is
    ///     `ModelPool.shared`, the pool that a Router uses when it gets no
    ///     pool.
    /// - Returns: the pooled model.
    static func pooledModel(of slot: RoutedLLM, from pool: ModelPool = .shared) -> PooledModel {
        PooledModel(ref: slot.chosen, pool: pool)
    }
}
