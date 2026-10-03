import Foundation
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter
import ScenarioGrading
import Synchronization
import Testing

/// Coverage for the Router adapters of this suite (`RouterDiscoverySeams`,
/// `SelectionGrammar`, `RoutedAgentSession`, and the pooled embedder of
/// `RouterDiscoverySeams.acquireEmbedder`).
///
/// Discovery takes the registry seams and knows nothing of Router. These
/// adapters are where the suite turns the Router handles of a resolved profile
/// into those seams. Every Router handle here comes from `makeStubProfile()`,
/// so no test loads a model.
@Suite("RouterDiscoverySeams")
struct RouterDiscoverySeamsTests {
    /// The JSON Schema text of `grammar`, or `nil` when it is not a
    /// `.jsonSchema` grammar.
    ///
    /// - Parameter grammar: the grammar to read.
    /// - Returns: the schema text, or `nil`.
    private static func jsonSchemaSource(of grammar: Grammar) -> String? {
        if case .jsonSchema(let source) = grammar { return source }
        return nil
    }

    /// Decodes the schema JSON out of a built `Grammar`, failing the test if
    /// the grammar isn't a `.jsonSchema` case or the source isn't a JSON
    /// object.
    ///
    /// - Parameter grammar: the grammar to decode.
    /// - Returns: the parsed schema as a `[String: Any]` dictionary.
    private static func decodeSchema(_ grammar: Grammar) throws -> [String: Any] {
        let source = try #require(jsonSchemaSource(of: grammar))
        let object = try JSONSerialization.jsonObject(with: Data(source.utf8))
        return try #require(object as? [String: Any])
    }

    /// The `ids` array subschema of a decoded selection schema.
    ///
    /// - Parameter schema: the decoded schema.
    /// - Returns: the subschema of the `ids` property.
    private static func idsSchema(of schema: [String: Any]) throws -> [String: Any] {
        let properties = try #require(schema["properties"] as? [String: Any])
        return try #require(properties["ids"] as? [String: Any])
    }

    /// The session factory of `source`, or `nil` when the source holds one
    /// fixed session.
    ///
    /// - Parameter source: the session source of a selection configuration.
    /// - Returns: the factory that makes one session per instruction text, or
    ///   `nil`.
    private static func sessionFactory(
        of source: SelectionSessionSource
    ) -> (@Sendable (String) async throws -> any AgentSession)? {
        if case .factory(let makeSession) = source { return makeSession }
        return nil
    }

    /// The group name of the qualified path in the registry of
    /// ``grammarConstrainedToSurfaceEntryPaths()``.
    private static let weatherGroup = "weather"

    // MARK: - SelectionGrammar

    @Test("the schema's top-level type is object with ids required")
    func schemaTopLevelShapeIsObjectRequiringIds() throws {
        let schema = try Self.decodeSchema(SelectionGrammar.idEnumGrammar(ids: ["alpha.beta", "gamma.delta"]))

        #expect(schema["type"] as? String == "object")
        #expect(schema["required"] as? [String] == ["ids"])
    }

    @Test("the schema's ids property is a uniqueItems array of the given enum ids")
    func schemaIdsPropertyIsUniqueEnumArray() throws {
        let ids = ["alpha.beta", "gamma.delta", "epsilon.zeta"]
        let idsSchema = try Self.idsSchema(of: Self.decodeSchema(SelectionGrammar.idEnumGrammar(ids: ids)))

        #expect(idsSchema["type"] as? String == "array")
        #expect(idsSchema["uniqueItems"] as? Bool == true)
        #expect(idsSchema["maxItems"] as? Int == ids.count)

        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["type"] as? String == "string")
        #expect(items["enum"] as? [String] == ids)
    }

    @Test("an empty ids input still produces a well-formed schema with an empty enum")
    func emptyIdsProducesWellFormedSchemaWithEmptyEnum() throws {
        let idsSchema = try Self.idsSchema(of: Self.decodeSchema(SelectionGrammar.idEnumGrammar(ids: [])))

        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["enum"] as? [String] == [])
    }

    @Test("the grammar over a real registry's entry paths constrains the enum to exactly those paths, qualified paths included")
    func grammarConstrainedToSurfaceEntryPaths() throws {
        let log = ScenarioCallLog()
        let registry = try MultiTool.Builder()
            .addTool(IntegrationTripTool(log: log))
            .addGroup(named: Self.weatherGroup, [IntegrationWeatherTool(log: log)])
            .buildRegistry()

        let idsSchema = try Self.idsSchema(
            of: Self.decodeSchema(SelectionGrammar.idEnumGrammar(ids: registry.surface.entries.map(\.path))))

        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(
            items["enum"] as? [String]
                == [IntegrationTripTool.path, "\(Self.weatherGroup).\(IntegrationWeatherTool.path)"])
    }

    // MARK: - The selection factory

    @Test("the selection factory makes every session of the tier a routed session under the grammar of the catalog ids")
    func selectionSessionsCarryTheIdGrammar() async throws {
        // The closure holds the profile and not only its handle: a handle
        // holds its profile weakly, and a released profile stops `makeSession`.
        let profile = try await makeStubProfile()
        let recordedGrammars = Mutex<[Grammar]>([])
        let ids = ["getTrip", "github.createIssue"]

        let factory = RouterDiscoverySeams.makeSelection { grammar, instructions in
            recordedGrammars.withLock { $0.append(grammar) }
            return profile.flash.makeGuidedSession(grammar: grammar, instructions: instructions)
        }
        let makeSession = try #require(Self.sessionFactory(of: factory(ids).sessionSource))
        let first = try await makeSession("first instructions")
        let second = try await makeSession("second instructions")

        // One grammar, built one time for the catalog, under both sessions.
        let recorded = recordedGrammars.withLock { $0 }
        #expect(recorded.count == 2)
        #expect(recorded.first == recorded.last)
        // The schema is compared decoded: `JSONSerialization` gives no fixed
        // key order, so two encodings of one schema can differ as text.
        let grammar = try #require(recorded.first)
        let expected = try SelectionGrammar.idEnumGrammar(ids: ids)
        let recordedSchema = NSDictionary(dictionary: try Self.decodeSchema(grammar))
        #expect(recordedSchema == NSDictionary(dictionary: try Self.decodeSchema(expected)))
        #expect(first is RoutedAgentSession)
        #expect(second is RoutedAgentSession)
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

    // MARK: - The pooled embedder and the sample session

    /// A pool loader that counts its loads and gives a stub embedding model.
    ///
    /// A test makes a pool with `ModelPool(loader:)` over it, gives that pool
    /// to `RouterDiscoverySeams.acquireEmbedder`, and reads ``loads``: each
    /// load is one embedding model that the pool put in memory.
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
        let vectors = try await seams.embedder.embed(Self.texts)

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

    @Test("two embedders of the embedding model in one pool load the model one time, through the loader of the pool")
    func twoEmbeddersOfTheEmbeddingModelLoadOneModel() async throws {
        let profile = try await makeStubProfile(embeddingModel: embeddingModel, pool: ModelPool())
        let loader = CountingEmbeddingLoader()
        let pool = ModelPool(loader: loader)

        let first = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)
        let second = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding, from: pool)
        _ = try await first.embed(Self.texts)
        _ = try await second.embed(Self.texts)

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
        let vectors = try await embedder.embed(Self.texts)

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

    @Test("the sample session is absent with no generator, and a routed session on the generator otherwise")
    func sampleSessionFollowsTheGenerator() async throws {
        let profile = try await makeStubProfile()
        let embedder = Self.pooledEmbedder(of: profile)

        let withoutGenerator = RouterDiscoverySeams(librarian: profile.flash, embedder: embedder)
        let withGenerator = RouterDiscoverySeams(
            librarian: profile.flash, embedder: embedder, sampleGenerator: profile.standard)

        #expect(withoutGenerator.sampleSession == nil)
        let makeSession = try #require(withGenerator.sampleSession)
        // A handle holds its profile weakly, so the profile must live until
        // the session is made.
        withExtendedLifetime(profile) {
            #expect(makeSession("instructions") is RoutedAgentSession)
        }
    }

    // MARK: - The same-model refusal names the fix (^zhmqvxb)

    /// The model the refusal names: the model of the calling session.
    private static let callerModel = stubStandardModel

    /// The sentence of ``SameModelDiscoveryError`` that names the fix, written
    /// out here so that a reword of the error fails this suite.
    private static let fixSentence =
        "The librarian model must be different from the model of the calling session."

    @Test("the adapter turns Router's same-model refusal into an error that names the model and the fix")
    func sameModelRefusalNamesTheFix() throws {
        let refusal = GenerationQueueError.waitInsideOpenSubmission(model: Self.callerModel)

        let explained = try #require(RoutedAgentSession.explained(refusal) as? SameModelDiscoveryError)

        #expect(explained.model == Self.callerModel)
        #expect(String(describing: explained).contains(Self.callerModel.stringValue))
        #expect(String(describing: explained).contains(Self.fixSentence))
        #expect(explained.errorDescription == String(describing: explained))
    }

    @Test("the adapter passes every other error through unchanged")
    func otherErrorsPassThroughUnchanged() {
        let explained = RoutedAgentSession.explained(DiscoverySearchFailure())

        #expect(explained as? DiscoverySearchFailure == DiscoverySearchFailure())
    }

    @Test("a searchTools call whose librarian is refused on the model of the calling session gives the error that names the fix")
    func refusedLibrarianGivesTheFixAsTheToolError() async throws {
        let registry = try MultiTool.Builder().addTool(IntegrationTripTool(log: ScenarioCallLog())).buildRegistry()
        let explained = RoutedAgentSession.explained(
            GenerationQueueError.waitInsideOpenSubmission(model: Self.callerModel))
        let tool = try SearchToolsTool(registry: registry, selection: { _ in
            SelectionConfig(model: { _ in FailingAgentSession(error: explained) }, capacityCharacterLimit: .max)
        })

        let thrown = await #expect(throws: SameModelDiscoveryError.self) {
            try await tool.call(arguments: SearchToolsArguments(task: "list the trip cities"))
        }

        // Router shows a failed tool call to the model as
        // `String(describing: error)`, so that text must name the fix.
        #expect(String(describing: try #require(thrown)).contains(Self.fixSentence))
    }
}

/// An error that is not Router's same-model refusal, so
/// `RoutedAgentSession.explained(_:)` must give it back unchanged.
private struct DiscoverySearchFailure: Error, Equatable {}

/// A selection root that fails each call with one error.
private final class FailingAgentSession: AgentSession, Sendable {
    /// The error each call throws.
    private let error: any Error

    /// Makes a session that fails with `error`.
    ///
    /// - Parameter error: the error each call throws.
    init(error: any Error) {
        self.error = error
    }

    func respond(to prompt: String) async throws -> String {
        throw error
    }

    func fork() async throws -> any AgentSession {
        throw error
    }
}
