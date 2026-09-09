import FoundationModelsMetadataRegistry

/// A searcher over one catalog, and the embedding of that catalog it fills
/// in one time before its first search.
///
/// **Why the embedding is filled here and not where the searcher is built.**
/// A bundle is built synchronously: `RegistryBundle.init` runs under the
/// holder's lock at every surface swap, and `makeSessionToolsAndStaging`
/// starts no task of its own (`SurfaceRefresher.swift` states that rule).
/// Embedding a catalog is an `async` call on a model. The registry's own
/// hot-reload path is the seam that reconciles the two:
/// `MetadataSearcher.update(items:)` embeds the items the index carries no
/// vector for, merges the vectors in place, and keeps the selection tier and
/// its cached root session. So the searcher is built over an index with no
/// vectors, the first search pays the embed, and every later search finds it
/// done. Until that first search the catalog is keyword-searchable, which is
/// what the registry promises of an index that is still catching up.
///
/// A searcher built with no embedder skips the step and stays what it was:
/// BM25 and trigram alone, with the registry reporting
/// `.embeddingUnavailable` on each search.
///
/// **This type is a bridge, and its permanent home is the registry.** The
/// one-time catch-up before the first search is a behavior of the searcher,
/// not of this package: registry card `^8c4wtra` asks `MetadataSearcher` to
/// run it itself when it was built synchronously with an embedder. When that
/// lands, `RegistryBundle` passes the embedder to `MetadataSearcher` directly
/// and this file is deleted (card `^zqz1zan`, direction part 4).
struct CatalogSearcher: Sendable {
    /// The searcher every search goes to.
    let searcher: MetadataSearcher<APISurface.Entry>

    /// The embedding to fill before the first search, or `nil` when this
    /// searcher ranks with no embedder.
    private let embedding: CatalogEmbedding?

    /// Wraps a searcher that was built elsewhere and fills no embedding of
    /// its own — a scripted or keyword-only searcher a test supplies through
    /// `SearchToolsTool.init(searcher:limit:sample:)`.
    ///
    /// - Parameter searcher: The searcher every search goes to.
    init(searcher: MetadataSearcher<APISurface.Entry>) {
        self.searcher = searcher
        self.embedding = nil
    }

    /// Builds a searcher over `entries`, ranking with `embedder` from its first
    /// search on.
    ///
    /// The index is built here, synchronously and with no vectors; `embedder`
    /// fills them at the first search. A `nil` embedder builds the same
    /// searcher with nothing to fill.
    ///
    /// - Parameters:
    ///   - entries: The catalog to index.
    ///   - mode: Which tier `search(intent:limit:)` uses.
    ///   - embedder: The embedder that embeds every block at the first search
    ///     and the query at each search, or `nil` for keyword-only ranking.
    ///   - selection: The selection tier, or `nil` for retrieval alone.
    init(
        over entries: [APISurface.Entry],
        mode: SearchMode,
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig?
    ) {
        let searcher = MetadataSearcher(
            index: MetadataIndex(items: entries), mode: mode, embedder: embedder, selection: selection)
        self.searcher = searcher
        self.embedding = embedder.map { _ in CatalogEmbedding(searcher: searcher, entries: entries) }
    }

    /// Searches the catalog for `intent`, after the embedding is filled.
    ///
    /// - Parameters:
    ///   - intent: The plain-language search intent.
    ///   - limit: The maximum number of matches to return.
    /// - Returns: What `MetadataSearcher.search(intent:limit:)` answers.
    /// - Throws: What `MetadataSearcher.search(intent:limit:)` throws.
    func search(intent: String, limit: Int) async throws -> [Match<APISurface.Entry>] {
        await embedding?.fill()
        return try await searcher.search(intent: intent, limit: limit)
    }
}

/// The one-time embed of one searcher's catalog.
///
/// An actor, because the first search of a searcher fills it and every later
/// search reads that it is filled, and two searches can arrive together.
/// Two callers that both read "not filled" both run `update(items:)`, and
/// that is safe: the registry's update is hash-guarded and idempotent, so the
/// second call merges nothing the first did not, at the cost of one more
/// embed on that one race. What the flag prevents is the every-call cost of
/// re-rendering and re-tokenizing the catalog, which `update(items:)` pays
/// before its hash guard answers.
///
/// A transient embed failure leaves the searcher keyword-only for the life of
/// its bundle. The registry reports that on every search, and the next
/// surface swap builds a fresh bundle that embeds again.
actor CatalogEmbedding {
    /// The searcher whose index the embed fills.
    private let searcher: MetadataSearcher<APISurface.Entry>

    /// The catalog the searcher was built over, handed to `update(items:)`
    /// unchanged so the update embeds and never rebuilds.
    private let entries: [APISurface.Entry]

    /// Whether `fill()` has run `update(items:)` to completion.
    private var isFilled = false

    /// Creates the embed of `entries` into `searcher`, not yet run.
    ///
    /// - Parameters:
    ///   - searcher: The searcher whose index the embed fills.
    ///   - entries: The catalog the searcher was built over.
    init(searcher: MetadataSearcher<APISurface.Entry>, entries: [APISurface.Entry]) {
        self.searcher = searcher
        self.entries = entries
    }

    /// Fills the embedding, the first time; answers at once every later time.
    func fill() async {
        guard !isFilled else { return }
        await searcher.update(items: entries)
        isFilled = true
    }
}
