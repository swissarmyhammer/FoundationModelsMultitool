import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the embedder the discovery and hint searchers rank with
/// (card `^zqz1zan`).
///
/// The `acp-agent` log of the SWE-bench run said, on every `searchTools`
/// call, `no embedder configured or catalog not yet embedded; results are
/// keyword-only`, although the agent's profile names an embedding model. The
/// embedder was resolved and resident, and nothing passed it into the
/// searchers. These tests hold the wiring that closes that gap:
///
/// 1. A bundle built with an embedder embeds its catalog ONE time, at the
///    first search, and every query once — through the discovery searcher
///    and through the hint searcher alike. Both searchers share that one
///    catalog embed, and each session with an equal catalog and the same
///    embedder shares it too (``SearchIndexCache``).
/// 2. The host-facing factories take the host's embedder as a
///    FoundationModelsExtras `PooledEmbedding`. The Router adapter has its own suite,
///    `RouterDiscoverySeamsTests`, in the nested `IntegrationTests` package.
/// 3. A catalog embed that fails leaves the searcher answering keyword-only
///    for the life of its bundle, and the next bundle embeds again.
///
/// No search here reaches a model: the searchers run in retrieval alone, and
/// the embedder is `RecordingEmbedder`, so the reading is the list of batches
/// it was handed.
@Suite("Discovery embedder")
struct DiscoveryEmbedderTests {
    /// A two-entry catalog, so a batch of "every summary block" is visibly a
    /// batch.
    private static func makeRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder(mode: .open).addTool(CitiesTool()).addTool(TempTool()).buildRegistry()
    }

    /// The shape `makeSessionToolsAndStaging` builds, with `embedder` in it and
    /// no selection tier, so every search is retrieval alone.
    private static func makeShape(embedder: (any PooledEmbedding)?) -> MultiTool.RegistryBundleShape {
        MultiTool.RegistryBundleShape(bindsSearchTools: true, discovery: .configured(selection: nil), embedder: embedder)
    }

    @Test("the discovery searcher embeds every catalog summary block one time at its first search, then each query once")
    func discoverySearcherEmbedsTheCatalogOnceAndEachQueryOnce() async throws {
        let registry = try Self.makeRegistry()
        let embedder = RecordingEmbedder()
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))
        let searcher = try #require(bundle.discoverySearcher)

        _ = try await searcher.search(intent: "trip cities", limit: 1)
        _ = try await searcher.search(intent: "temperature", limit: 1)

        // One batch of every summary block, in catalog order, and never a
        // second one: the second search embeds its query and nothing else.
        // The summary block is the embedded text of each entry (see
        // `APISurface+SearchableMetadata.swift`).
        #expect(embedder.batches == [registry.surface.entries.map(\.summaryBlock), ["trip cities"], ["temperature"]])
    }

    @Test("the hint searcher embeds the catalog and the guess through the same embedder")
    func hintSearcherEmbedsThroughTheEmbedder() async throws {
        let registry = try Self.makeRegistry()
        let embedder = RecordingEmbedder()
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))

        _ = try await bundle.hintSearcher.search(intent: "get itinerary", limit: 1)

        #expect(embedder.batches == [registry.surface.entries.map(\.summaryBlock), ["get itinerary"]])
    }

    @Test("a bundle built with no embedder embeds nothing and still answers")
    func bundleWithNoEmbedderStillAnswers() async throws {
        let registry = try Self.makeRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getCities" })
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: nil))
        let searcher = try #require(bundle.discoverySearcher)

        let matches = try await searcher.search(intent: "trip cities", limit: 1)

        #expect(matches.map(\.item.path) == [entry.path])
    }

    @Test("a failed catalog embed leaves the searcher answering, and the next bundle embeds again")
    func failedCatalogEmbedLeavesTheSearcherAnsweringAndTheNextBundleRetries() async throws {
        let registry = try Self.makeRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getCities" })
        let embedder = RecordingEmbedder(alwaysFails: true)
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))
        let searcher = try #require(bundle.discoverySearcher)

        // The searcher is still usable: the failed embed leaves it
        // keyword-only, and keyword-only still answers.
        let matches = try await searcher.search(intent: "trip cities", limit: 1)
        #expect(matches.map(\.item.path) == [entry.path])

        // And the failed catch-up runs one time for the life of this bundle:
        // the registry marks it done on every exit, a failure included.
        _ = try await searcher.search(intent: "trip cities", limit: 1)

        // A surface swap builds a fresh bundle, and that bundle embeds again.
        let nextBundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))
        _ = try await #require(nextBundle.discoverySearcher).search(intent: "trip cities", limit: 1)

        // The catalog summary-block batch, two times and never three: one per
        // bundle. No query batch at all — with no entry embedded, the
        // retrieval tier skips the cosine signal instead of embedding a query
        // it cannot use.
        let summaryBlocks = registry.surface.entries.map(\.summaryBlock)
        #expect(embedder.batches == [summaryBlocks, summaryBlocks])
    }

    @Test("makeSessionToolsAndStaging takes the host's embedder and still mounts a searchTools that answers")
    func sessionToolsTakeTheHostEmbedder() async throws {
        let registry = try Self.makeRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getCities" })
        let embedder = RecordingEmbedder()

        let mounted = try registry.makeSessionToolsAndStaging(selection: nil, embedder: embedder)
        let searchTools = try #require(mounted.tools.compactMap { $0 as? SearchToolsTool }.first)
        let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains(entry.block))
        // The first batch is the catalog, so the mounted searcher ranked with
        // the host's embedder and not with a copy of it.
        #expect(embedder.batches.first == registry.surface.entries.map(\.summaryBlock))
    }

    // MARK: - One catalog embed

    /// A struct embedder that a host makes again for each session, over one
    /// shared base embedder. It gives the base as its owner, so the cache
    /// knows that each value is the same embedder.
    private struct IdentifiedWrapper: IdentifiedEmbedding {
        /// The shared embedder that does the embeds.
        let base: RecordingEmbedder

        var embeddingOwner: any AnyObject & Sendable { base }

        func embed(texts: [String]) async throws -> [[Float]] {
            try await base.embed(texts: texts)
        }
    }

    /// A struct embedder with no identity, made again for each session.
    private struct AnonymousWrapper: PooledEmbedding {
        /// The shared embedder that does the embeds.
        let base: RecordingEmbedder

        func embed(texts: [String]) async throws -> [[Float]] {
            try await base.embed(texts: texts)
        }
    }

    /// Composes one session over a new registry with `embedder` and `cache`,
    /// and runs one `searchTools` call in it.
    ///
    /// A cached shared embed lives only while a session holds it. Thus a
    /// test that wants two sessions to share an embed keeps the tools of the
    /// first session while it composes the second.
    ///
    /// - Parameters:
    ///   - embedder: the embedder of the session.
    ///   - cache: the search index cache of the session.
    /// - Returns: the tools of the session, which keep the session open.
    /// - Throws: what composing the session or the search throws.
    @discardableResult
    private static func searchInNewSession(
        embedder: any PooledEmbedding, cache: SearchIndexCache
    ) async throws -> [any Tool] {
        let mounted = try Self.makeRegistry().makeSessionToolsAndStaging(
            selection: nil, embedder: embedder, sampleModel: nil, indexCache: cache)
        let searchTools = try #require(mounted.tools.compactMap { $0 as? SearchToolsTool }.first)
        _ = try await searchTools.call(arguments: SearchToolsArguments(task: "trip cities"))
        return mounted.tools
    }

    @Test("the hint searcher and the discovery searcher of one bundle embed the catalog one time")
    func bothSearchersOfOneBundleEmbedTheCatalogOneTime() async throws {
        let registry = try Self.makeRegistry()
        let embedder = RecordingEmbedder()
        let bundle = MultiTool.RegistryBundle(
            registry: registry,
            shape: MultiTool.RegistryBundleShape(
                bindsSearchTools: true, discovery: .configured(selection: nil), embedder: embedder,
                indexCache: SearchIndexCache()))

        _ = try await bundle.hintSearcher.search(intent: "get itinerary", limit: 1)
        _ = try await #require(bundle.discoverySearcher).search(intent: "trip cities", limit: 1)

        #expect(
            embedder.batches == [registry.surface.entries.map(\.summaryBlock), ["get itinerary"], ["trip cities"]])
    }

    @Test("two sessions with the same tool set and the same embedder object embed the catalog one time")
    func twoSessionsWithTheSameEmbedderObjectEmbedOneTime() async throws {
        let cache = SearchIndexCache()
        let embedder = RecordingEmbedder()

        let first = try await Self.searchInNewSession(embedder: embedder, cache: cache)
        let second = try await Self.searchInNewSession(embedder: embedder, cache: cache)

        let catalog = try Self.makeRegistry().surface.entries.map(\.summaryBlock)
        #expect(embedder.batches == [catalog, ["trip cities"], ["trip cities"]])
        #expect(cache.sharedEmbeddings == 1)
        withExtendedLifetime((first, second)) {}
    }

    @Test("two sessions with a new identified embedder value each embed the catalog one time")
    func twoSessionsWithAnIdentifiedEmbedderEmbedOneTime() async throws {
        let cache = SearchIndexCache()
        let base = RecordingEmbedder()

        let first = try await Self.searchInNewSession(embedder: IdentifiedWrapper(base: base), cache: cache)
        let second = try await Self.searchInNewSession(embedder: IdentifiedWrapper(base: base), cache: cache)

        let catalog = try Self.makeRegistry().surface.entries.map(\.summaryBlock)
        #expect(base.batches.filter { $0 == catalog }.count == 1)
        #expect(cache.sharedEmbeddings == 1)
        withExtendedLifetime((first, second)) {}
    }

    @Test("two sessions with an embedder that has no identity each embed the catalog")
    func twoSessionsWithAnAnonymousEmbedderEachEmbed() async throws {
        let cache = SearchIndexCache()
        let base = RecordingEmbedder()

        let first = try await Self.searchInNewSession(embedder: AnonymousWrapper(base: base), cache: cache)
        let second = try await Self.searchInNewSession(embedder: AnonymousWrapper(base: base), cache: cache)
        withExtendedLifetime((first, second)) {}

        let catalog = try Self.makeRegistry().surface.entries.map(\.summaryBlock)
        #expect(base.batches.filter { $0 == catalog }.count == 2)
        #expect(cache.sharedEmbeddings == 2)
        #expect(cache.builds == 1)
    }

    @Test("a failed shared embed is dropped, and the next session with the same embedder embeds again")
    func failedSharedEmbedIsDroppedFromTheCache() async throws {
        let cache = SearchIndexCache()
        let embedder = RecordingEmbedder(alwaysFails: true)

        let first = try await Self.searchInNewSession(embedder: embedder, cache: cache)
        let second = try await Self.searchInNewSession(embedder: embedder, cache: cache)
        withExtendedLifetime((first, second)) {}

        let catalog = try Self.makeRegistry().surface.entries.map(\.summaryBlock)
        #expect(embedder.batches == [catalog, catalog])
        #expect(cache.sharedEmbeddings == 2)
    }

    // MARK: - The cache keeps nothing alive

    /// Composes one session with a new embedder and an owner object, runs
    /// one search, and ends the session. Gives weak references to the owner
    /// and to the embedder, so the test can see whether anything keeps them.
    ///
    /// - Parameter cache: the search index cache of the session.
    /// - Returns: the weak references, after the session ended.
    /// - Throws: what composing the session or the search throws.
    private static func endedSession(
        cache: SearchIndexCache
    ) async throws -> (owner: WeakReference<RecordingEmbedder>, embedder: WeakReference<RecordingEmbedder>) {
        let owner = RecordingEmbedder()
        let embedder = RecordingEmbedder()
        try await Self.searchInNewSession(embedder: IdentifiedWrapper(base: owner), cache: cache)
        try await Self.searchInNewSession(embedder: embedder, cache: cache)
        return (WeakReference(owner), WeakReference(embedder))
    }

    @Test("after its sessions end, the cache keeps no embedder, no owner and no shared embed")
    func theCacheKeepsNoEmbedderAfterTheSessionsEnd() async throws {
        let cache = SearchIndexCache()

        let references = try await Self.endedSession(cache: cache)

        #expect(references.owner.object == nil)
        #expect(references.embedder.object == nil)
        #expect(cache.liveSharedEmbeddings == 0)
        #expect(cache.sharedEmbeddings == 2)
    }

    @Test("a session after the last session with the same embedder ended makes a new shared embed")
    func aSessionAfterTheLastSessionEndedMakesANewEmbed() async throws {
        let cache = SearchIndexCache()
        let embedder = RecordingEmbedder()

        try await Self.searchInNewSession(embedder: embedder, cache: cache)
        let open = try await Self.searchInNewSession(embedder: embedder, cache: cache)

        let catalog = try Self.makeRegistry().surface.entries.map(\.summaryBlock)
        #expect(embedder.batches.filter { $0 == catalog }.count == 2)
        #expect(cache.sharedEmbeddings == 2)
        #expect(cache.liveSharedEmbeddings == 1)
        withExtendedLifetime(open) {}
    }
}
