import FoundationModelsMetadataRegistry
import FoundationModelsRouter
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
///    and through the hint searcher alike.
/// 2. The host-facing factories take a Router `RoutedEmbedder` and adapt it
///    to the registry's `TextEmbedding` seam.
/// 3. A catalog embed that fails leaves the searcher answering keyword-only
///    for the life of its bundle, and the next bundle embeds again.
///
/// No search here reaches a model: the searchers run in retrieval alone, and
/// the embedder is `RecordingEmbedder`, so the reading is the list of batches
/// it was handed.
@Suite("Discovery embedder")
struct DiscoveryEmbedderTests {
    /// A two-entry catalog, so a batch of "every block" is visibly a batch.
    private static func makeRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).addTool(TempTool()).buildRegistry()
    }

    /// The shape `makeSessionToolsAndStaging` builds, with `embedder` in it and
    /// no selection tier, so every search is retrieval alone.
    private static func makeShape(embedder: (any TextEmbedding)?) -> MultiTool.RegistryBundleShape {
        MultiTool.RegistryBundleShape(bindsSearchTools: true, discovery: .configured(selection: nil), embedder: embedder)
    }

    @Test("the discovery searcher embeds every catalog block one time at its first search, then each query once")
    func discoverySearcherEmbedsTheCatalogOnceAndEachQueryOnce() async throws {
        let registry = try Self.makeRegistry()
        let embedder = RecordingEmbedder()
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))
        let searcher = try #require(bundle.discoverySearcher)

        _ = try await searcher.search(intent: "trip cities", limit: 1)
        _ = try await searcher.search(intent: "temperature", limit: 1)

        // One batch of every rendered block, in catalog order, and never a
        // second one: the second search embeds its query and nothing else.
        #expect(embedder.batches == [registry.surface.entries.map(\.block), ["trip cities"], ["temperature"]])
    }

    @Test("the hint searcher embeds the catalog and the guess through the same embedder")
    func hintSearcherEmbedsThroughTheEmbedder() async throws {
        let registry = try Self.makeRegistry()
        let embedder = RecordingEmbedder()
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: Self.makeShape(embedder: embedder))

        _ = try await bundle.hintSearcher.search(intent: "get itinerary", limit: 1)

        #expect(embedder.batches == [registry.surface.entries.map(\.block), ["get itinerary"]])
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

        // The catalog block batch, two times and never three: one per bundle.
        // No query batch at all — with no entry embedded, the retrieval tier
        // skips the cosine signal instead of embedding a query it cannot use.
        let blocks = registry.surface.entries.map(\.block)
        #expect(embedder.batches == [blocks, blocks])
    }

    @Test("the host's routed embedder is adapted to the registry's embedding seam unchanged")
    func routedEmbedderIsAdaptedUnchanged() async throws {
        let profile = try await makeStubProfile()

        let adapted = RoutedTextEmbedding(embedder: profile.embedding)
        let vectors = try await adapted.embed(["one", "two"])

        // `StubEmbeddingContainer` answers one constant vector per text; the
        // adapter forwards both members and adds nothing of its own.
        #expect(adapted.dimension == profile.embedding.dimension)
        #expect(vectors == (try await profile.embedding.embed(texts: ["one", "two"])))
    }

    @Test("makeSessionToolsAndStaging takes the host's embedder and still mounts a searchTools that answers")
    func sessionToolsTakeTheHostEmbedder() async throws {
        let registry = try Self.makeRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getCities" })
        let profile = try await makeStubProfile()

        let mounted = try registry.makeSessionToolsAndStaging(librarian: nil, embedder: profile.embedding)
        let searchTools = try #require(mounted.tools.compactMap { $0 as? SearchToolsTool }.first)
        let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains(entry.block))
    }
}
