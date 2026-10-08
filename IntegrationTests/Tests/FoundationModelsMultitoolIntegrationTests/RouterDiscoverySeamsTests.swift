import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter
import Synchronization
import Testing

/// Coverage for the Router adapter of this suite (`RouterDiscoverySeams`: the
/// pooled librarian, the pooled sample model, and the pooled embedder of
/// `RouterDiscoverySeams.acquireEmbedder`).
///
/// Discovery takes plain FoundationModels and FoundationModelsExtras types
/// and knows nothing of Router. This adapter is where the suite turns the
/// Router handles of a resolved profile into those seams. Every Router handle
/// here comes from `makeStubProfile()`, so no test loads a model.
@Suite("RouterDiscoverySeams")
struct RouterDiscoverySeamsTests {
    /// The catalog ids a test gives the selection factory.
    private static let catalogIDs = ["getTrip", "github.createIssue"]

    // MARK: - The selection factory

    @Test("the selection factory gives a pooled model of the model that the librarian slot chose")
    func selectionModelIsThePooledLibrarian() async throws {
        let profile = try await makeStubProfile()
        let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: Self.pooledEmbedder(of: profile))

        let config = try seams.selection(Self.catalogIDs)

        let model = try #require(config.model as? PooledModel)
        let librarian = RouterDiscoverySeams.pooledModel(of: profile.flash)
        #expect(model.executorConfiguration == librarian.executorConfiguration)
        // The calling session runs on `standard`, and the librarian must not.
        let caller = RouterDiscoverySeams.pooledModel(of: profile.standard)
        #expect(model.executorConfiguration != caller.executorConfiguration)
    }

    /// The sentence that decides the empty case, written out here on purpose.
    ///
    /// **Why a copy, when the tests read every other shipped string off the
    /// declaration that owns it.** This is the guard card `^zqz1zan` left
    /// behind. Measured on the agent's flash model: under the ranker default
    /// that shipped before this sentence, `mlx-community/Qwen3-4B-4bit`
    /// answered eight of the agent's ten queries with `{"ids":[]}` — every
    /// query for a way to write, edit or run — and the bench run ended with an
    /// empty patch. The ranker's `String.selectionDefault` carries the
    /// sentence itself, so this host passes no preamble of its own. The
    /// ranker commit `dbda1ae` gave the default new words for this 4B model:
    /// the sentence "Prefer the closest candidates over an empty answer" is
    /// gone, and the default now says when an empty answer is correct.
    ///
    /// A test that read the sentence off `String.selectionDefault` would hold
    /// whatever that constant said, which is the one thing this guard must not
    /// do. A copy fails loudly if a later ranker default drops the sentence.
    private static let emptyAnswerSentence =
        "Answer with an empty list only when no candidate is related to the request at all."

    @Test("the selection tier is seeded with a preamble that tells the model to answer with an empty list only when no candidate is related to the request")
    func selectionTierIsSeededWithTheEmptyAnswerGuidance() async throws {
        let profile = try await makeStubProfile()

        let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: Self.pooledEmbedder(of: profile))
        let config = try seams.selection(["getTrip"])

        #expect(config.preamble.contains(Self.emptyAnswerSentence))
    }

    // MARK: - The pooled embedder and the sample model

    /// A pool loader that counts its loads and gives a stub embedding model.
    ///
    /// A test makes a pool with `ModelPool(loader:)` over it, gives that pool
    /// to `RouterDiscoverySeams.acquireEmbedder` or
    /// `RouterDiscoverySeams.pooledModel`, and reads ``loads``: each load is
    /// one model that the pool put in memory.
    private final class CountingEmbeddingLoader: PooledModelLoader {
        /// The number of ``load(_:)`` calls.
        private let loadCount = Mutex(0)

        /// The number of models that this loader loaded.
        var loads: Int { loadCount.withLock { $0 } }

        func load(_ key: ModelPoolKey) async throws -> any Sendable {
            loadCount.withLock { $0 += 1 }
            return StubEmbeddingContainer()
        }

        func evict(_ container: any Sendable) async {}
    }

    /// The pooled embedder of the embedding slot of `profile`, from
    /// `ModelPool.shared`, where `makeStubProfile()` resolves by default.
    ///
    /// - Parameter profile: the resolved stub profile.
    /// - Returns: the pooled embedder.
    private static func pooledEmbedder(of profile: LanguageModelProfile) -> PooledEmbedder {
        RouterDiscoverySeams.acquireEmbedder(for: profile.embedding)
    }

    /// The pool key of the embedding model of this suite, `embeddingModel`.
    private static let embeddingKey = ModelPoolKey(ref: embeddingModel, role: .embedding)

    /// The texts each embed call of this suite sends.
    private static let texts = ["one", "two"]

    @Test("the seams rank with the pooled embedder of the resolved embedding model")
    func seamsRankWithThePooledEmbedder() async throws {
        let profile = try await makeStubProfile()

        let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: Self.pooledEmbedder(of: profile))
        let vectors = try await seams.embedder.embed(texts: Self.texts)

        // The pooled embedder forwards to the container that the Router
        // loaded, so it gives the vectors of the Router embedding handle.
        #expect(seams.embedder is PooledEmbedder)
        #expect(vectors == (try await profile.embedding.embed(texts: Self.texts)))
    }

    @Test("the embedder loads nothing when it is made")
    func embedderLoadsNothingWhenItIsMade() async throws {
        // The Router resolves into its own pool, so the discovery pool below
        // starts empty, and no stub container goes into `ModelPool.shared`
        // under the key of a real model.
        let profile = try await makeStubProfile(embeddingModel: embeddingModel, pool: ModelPool())
        let loader = CountingEmbeddingLoader()
        let pool = ModelPool(loader: loader)

        let embedder = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)

        #expect(loader.loads == 0)
        #expect(!pool.isResident(Self.embeddingKey))
        withExtendedLifetime(embedder) {}
    }

    @Test("a pooled model of a generation slot loads nothing when it is made")
    func pooledModelLoadsNothingWhenItIsMade() async throws {
        let profile = try await makeStubProfile(pool: ModelPool())
        let loader = CountingEmbeddingLoader()
        let pool = ModelPool(loader: loader)

        let librarian = RouterDiscoverySeams.pooledModel(of: profile.flash, from: pool)

        #expect(loader.loads == 0)
        #expect(pool.residentModelCount == 0)
        withExtendedLifetime(librarian) {}
    }

    @Test("two embedders of the embedding model in one pool load the model one time, through the loader of the pool")
    func twoEmbeddersOfTheEmbeddingModelLoadOneModel() async throws {
        let profile = try await makeStubProfile(embeddingModel: embeddingModel, pool: ModelPool())
        let loader = CountingEmbeddingLoader()
        let pool = ModelPool(loader: loader)

        let first = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)
        let second = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)
        _ = try await first.embed(texts: Self.texts)
        _ = try await second.embed(texts: Self.texts)

        #expect(loader.loads == 1)
        #expect(pool.residentModelCount == 1)
        #expect(pool.isResident(Self.embeddingKey))
        withExtendedLifetime((first, second)) {}
    }

    @Test("the Router embedding slot and the discovery embedder share one resident model")
    func embeddingSlotAndDiscoveryEmbedderShareOneResidentModel() async throws {
        let loader = CountingEmbeddingLoader()
        let pool = ModelPool(loader: loader)
        let profile = try await makeStubProfile(embeddingModel: embeddingModel, pool: pool)
        let residentBefore = pool.residentModelCount

        let embedder = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)
        let vectors = try await embedder.embed(texts: Self.texts)

        // The pool gives a hold of the model that the Router loaded: its own
        // loader loads nothing, and no second model goes into memory.
        #expect(loader.loads == 0)
        #expect(pool.residentModelCount == residentBefore)
        #expect(pool.isResident(Self.embeddingKey))
        #expect(vectors == (try await profile.embedding.embed(texts: Self.texts)))
        // The profile keeps the holds of the Router. Without it, the pool
        // can evict the model before the checks above run.
        withExtendedLifetime((profile, embedder)) {}
    }

    @Test("the sample model is absent with no generator, and a pooled model of the generator slot otherwise")
    func sampleModelFollowsTheGenerator() async throws {
        let profile = try await makeStubProfile()
        let embedder = Self.pooledEmbedder(of: profile)

        let withoutGenerator = RouterDiscoverySeams(librarian: profile.flash, embedder: embedder)
        let withGenerator = RouterDiscoverySeams(
            librarian: profile.flash, embedder: embedder, sampleGenerator: profile.standard)

        #expect(withoutGenerator.sampleModel == nil)
        let sampleModel = try #require(withGenerator.sampleModel as? PooledModel)
        let generator = RouterDiscoverySeams.pooledModel(of: profile.standard)
        #expect(sampleModel.executorConfiguration == generator.executorConfiguration)
    }
}
