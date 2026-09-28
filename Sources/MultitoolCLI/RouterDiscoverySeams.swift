import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter

/// The discovery seams of `FoundationModelsMultitool`, over the Router
/// handles of a resolved profile.
///
/// Discovery takes the seams of FoundationModelsMetadataRegistry and knows
/// nothing of Router: a ``SearchToolsTool/SelectionFactory``, an
/// `any TextEmbedding` and a ``SearchToolsTool/SessionFactory``. The host
/// picks the models. This is the one place where the sample CLI turns its
/// Router handles into those seams, and `CLIRunner` mounts its session tools
/// with the result:
///
/// ```swift
/// let embedder = try await RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, loader: loader)
/// let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: embedder)
/// let mounted = try registry.makeSessionToolsAndStaging(
///     selection: seams.selection, embedder: seams.embedder, sampleSession: seams.sampleSession)
/// ```
public struct RouterDiscoverySeams: Sendable {
    /// Makes the selection tier for the catalog ids, on guided sessions of
    /// the librarian.
    public let selection: SearchToolsTool.SelectionFactory

    /// The pooled embedder both searchers rank with. It keeps a hold of the
    /// embedding model in the model pool of the process.
    public let embedder: any TextEmbedding

    /// Makes the sample-snippet session on the generator, or `nil` when no
    /// generator was given and `searchTools` answers with signatures alone.
    public let sampleSession: SearchToolsTool.SessionFactory?

    /// Makes the seams over the Router handles of a resolved profile.
    ///
    /// - Parameters:
    ///   - librarian: the model every selection session runs on. It must be
    ///     a model other than the model of the session that mounts
    ///     `searchTools` — see ``makeSelection(makeGuidedSession:)``. The
    ///     sample CLI passes `profile.flash`, and `CLIRunner.demoProfile`
    ///     puts a different model in `flash` than in `standard`.
    ///   - embedder: the pooled embedder both searchers rank with. The
    ///     sample CLI passes the result of
    ///     ``acquireEmbedder(for:loader:from:)`` for `profile.embedding`.
    ///   - sampleGenerator: the model the sample snippet is written on, or
    ///     `nil` (the default) for no sample. It must also be a model other
    ///     than the model of the session that mounts `searchTools`, for the
    ///     same reason as the librarian. Thus the main generation slot, which
    ///     drives that session, is not a correct generator. Its session is
    ///     made with no `tools:` argument, which keeps `searchTools` off it:
    ///     it writes a snippet, it does not execute one.
    public init(librarian: RoutedLLM, embedder: PooledTextEmbedding, sampleGenerator: RoutedLLM? = nil) {
        self.selection = Self.makeSelection { grammar, instructions in
            librarian.makeGuidedSession(grammar: grammar, instructions: instructions)
        }
        self.embedder = embedder
        self.sampleSession = sampleGenerator.map(Self.makeSampleSession(generator:))
    }

    /// Acquires the pooled embedder for the embedding slot of a resolved
    /// profile, by the `ModelRef` that the slot chose.
    ///
    /// The Router resolves each profile into its model pool, and the default
    /// pool is `ModelPool.shared`, the pool of the process. When the Router
    /// resolved `embedding` into `pool`, the model is resident: the pool adds
    /// a hold and does not call `loader`. Thus the Router, the registry and
    /// this host use one embedding model in memory. When the model is not
    /// resident, the pool loads it through `loader`.
    ///
    /// - Parameters:
    ///   - embedding: the embedding handle of a resolved profile. Its
    ///     `chosen` model is the pool key, and its `footprintBytes` is the
    ///     footprint that the pool counts when this call loads the model.
    ///   - loader: the loader that loads the model when it is not resident.
    ///     The sample CLI passes the `LiveModelLoader` of its Router.
    ///   - pool: the pool to acquire the model from. The default is
    ///     `ModelPool.shared`, the pool that a Router uses when it gets no
    ///     pool.
    /// - Returns: the pooled embedder. It keeps a hold of the model, so the
    ///   model stays resident while the embedder exists.
    /// - Throws: what `loader` throws, or `PooledEmbedderError.notAnEmbedding`
    ///   when the container of the key is not a `PooledEmbedding`.
    public static func acquireEmbedder(
        for embedding: RoutedEmbedder,
        loader: any PooledModelLoader,
        from pool: ModelPool = .shared
    ) async throws -> PooledTextEmbedding {
        try await PooledTextEmbedding.acquire(
            embedding.chosen, footprintBytes: embedding.footprintBytes, loader: loader, from: pool)
    }

    /// The session factory over `generator`: one plain Router session per
    /// instruction text, with no tools mounted.
    ///
    /// - Parameter generator: the model the sample snippet is written on.
    /// - Returns: the session factory.
    static func makeSampleSession(generator: RoutedLLM) -> SearchToolsTool.SessionFactory {
        { instructions in
            RoutedAgentSession(session: generator.makeSession(instructions: instructions))
        }
    }

    /// The selection factory over `makeGuidedSession`: for each catalog, one
    /// id grammar, and every session of the tier made under it.
    ///
    /// **One grammar for every call, built before the session factory rather
    /// than inside it.** `SelectionConfig`'s factory takes the instructions
    /// alone as of the ranker's `34fe8d4`, so a grammar scoped to one round's
    /// candidates is not expressible. Over budget, the tier prompts one slice
    /// of the catalog at a time while this grammar still permits every id in
    /// the catalog. That is safe: the tier's own `.unknownSelectedId` filter
    /// drops an id outside the slice the prompt carried.
    ///
    /// **The selection session must run on a model other than the model of
    /// the session whose turn calls `searchTools`. That is a correctness
    /// requirement, not a cost preference.** `searchTools` is synchronous, so
    /// its body runs inside the open submission of the calling session.
    /// Router runs the work of each model in order on one FIFO queue. A
    /// session on a different model waits its turn on the queue of that
    /// model, and the search completes. A session on the same model would
    /// wait for the open submission to end, and that submission ends only
    /// when this tool returns. Router refuses that wait at once with
    /// `GenerationQueueError.waitInsideOpenSubmission`, and
    /// ``RoutedAgentSession`` turns the refusal into a
    /// ``SameModelDiscoveryError`` whose text names the fix. What keeps this
    /// host clear of it is that `CLIRunner.demoProfile` puts a different
    /// model in `flash` than in `standard`.
    ///
    /// Thus do not reuse or fork the session of the caller here. It looks
    /// like the natural simplification, and it is the one change this
    /// factory must never take.
    ///
    /// - Parameter makeGuidedSession: makes one guided Router session from a
    ///   grammar and the instructions. ``init(librarian:embedder:sampleGenerator:)``
    ///   passes the librarian's `makeGuidedSession(grammar:instructions:)`, and a
    ///   test passes a closure that records the grammar.
    /// - Returns: the selection factory.
    static func makeSelection(
        makeGuidedSession: @escaping @Sendable (Grammar, String) -> any RoutedSession
    ) -> SearchToolsTool.SelectionFactory {
        { ids in
            let grammar = try SelectionGrammar.idEnumGrammar(ids: ids)
            return SelectionConfig(model: { instructions in
                RoutedAgentSession(session: makeGuidedSession(grammar, instructions))
            })
        }
    }
}
