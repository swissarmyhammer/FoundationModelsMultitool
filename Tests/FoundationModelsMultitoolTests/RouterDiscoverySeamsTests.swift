import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter
import Synchronization
import Testing

@testable import MultitoolCLI

/// Coverage for the Router adapters of the sample CLI (`RouterDiscoverySeams`,
/// `SelectionGrammar`, `RoutedAgentSession`, `RoutedTextEmbedding`).
///
/// Discovery takes the registry seams and knows nothing of Router. These
/// adapters are where the host turns the Router handles of a resolved profile
/// into those seams. Every Router handle here comes from `makeStubProfile()`,
/// so no test loads a model.
@Suite("RouterDiscoverySeams")
struct RouterDiscoverySeamsTests {
    /// The error ``sessionFactory(of:)`` throws for a source that holds one
    /// fixed session and no factory.
    private struct NotASessionFactory: Error {}

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

    /// The session factory of `source`.
    ///
    /// - Parameter source: the session source of a selection configuration.
    /// - Returns: the factory that makes one session per instruction text.
    /// - Throws: ``NotASessionFactory`` when `source` holds one fixed session.
    private static func sessionFactory(
        of source: SelectionSessionSource
    ) throws -> @Sendable (String) -> any AgentSession {
        switch source {
        case .factory(let makeSession):
            return makeSession
        case .session:
            throw NotASessionFactory()
        }
    }

    /// The `ids` array subschema of a decoded selection schema.
    ///
    /// - Parameter schema: the decoded schema.
    /// - Returns: the subschema of the `ids` property.
    private static func idsSchema(of schema: [String: Any]) throws -> [String: Any] {
        let properties = try #require(schema["properties"] as? [String: Any])
        return try #require(properties["ids"] as? [String: Any])
    }

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
        let registry = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addGroup(named: "github", [GithubCreateIssueTool()])
            .buildRegistry()

        let idsSchema = try Self.idsSchema(
            of: Self.decodeSchema(SelectionGrammar.idEnumGrammar(ids: registry.surface.entries.map(\.path))))

        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["enum"] as? [String] == ["getTrip", "github.createIssue"])
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
        let makeSession = try Self.sessionFactory(of: try factory(ids).sessionSource)
        let first = makeSession("first instructions")
        let second = makeSession("second instructions")

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
    /// empty patch. The ranker's `String.selectionDefault` now carries the
    /// sentence itself (ranker card `^zxm99zs`), so this host passes no
    /// preamble of its own.
    ///
    /// A test that read the sentence off `String.selectionDefault` would hold
    /// whatever that constant said, which is the one thing this guard must not
    /// do. A copy fails loudly if a later ranker default drops the sentence.
    private static let emptyAnswerSentence =
        "Prefer the closest candidates over an empty answer; answer with an empty list only when "
        + "no candidate is related to the task at all."

    @Test("the selection tier is seeded with a preamble that tells the model to prefer the closest candidates over an empty answer")
    func selectionTierIsSeededWithTheEmptyAnswerGuidance() async throws {
        let profile = try await makeStubProfile()

        let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: profile.embedding)
        let config = try seams.selection(["getTrip"])

        #expect(config.preamble.contains(Self.emptyAnswerSentence))
    }

    // MARK: - The embedding and the sample session

    @Test("the host's routed embedder is adapted to the registry's embedding seam unchanged, dimension included")
    func routedEmbedderIsAdaptedUnchanged() async throws {
        let profile = try await makeStubProfile()

        let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: profile.embedding)
        let vectors = try await seams.embedder.embed(["one", "two"])

        // `StubEmbeddingContainer` answers one constant vector per text; the
        // adapter forwards both members and adds nothing of its own.
        #expect(seams.embedder is RoutedTextEmbedding)
        #expect(seams.embedder.dimension == profile.embedding.dimension)
        #expect(vectors == (try await profile.embedding.embed(texts: ["one", "two"])))
    }

    @Test("the sample session is absent with no generator, and a routed session on the generator otherwise")
    func sampleSessionFollowsTheGenerator() async throws {
        let profile = try await makeStubProfile()

        let withoutGenerator = RouterDiscoverySeams(librarian: profile.flash, embedder: profile.embedding)
        let withGenerator = RouterDiscoverySeams(
            librarian: profile.flash, embedder: profile.embedding, sampleGenerator: profile.standard)

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
    private static let callerModel: ModelRef = "stub/standard"

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
        let explained = RoutedAgentSession.explained(SelectionSearchFailure())

        #expect(explained as? SelectionSearchFailure == SelectionSearchFailure())
    }

    @Test("a searchTools call whose librarian is refused on the model of the calling session gives the error that names the fix")
    func refusedLibrarianGivesTheFixAsTheToolError() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()
        let explained = RoutedAgentSession.explained(
            GenerationQueueError.waitInsideOpenSubmission(model: Self.callerModel))
        let tool = try SearchToolsTool(registry: registry, selection: { _ in
            SelectionConfig(model: { _ in FailingSelectionRootSession(error: explained) }, capacityCharacterLimit: .max)
        })

        let thrown = await #expect(throws: SameModelDiscoveryError.self) {
            try await tool.call(arguments: SearchToolsArguments(task: "list the trip cities"))
        }

        // Router shows a failed tool call to the model as
        // `String(describing: error)`, so that text must name the fix.
        #expect(String(describing: try #require(thrown)).contains(Self.fixSentence))
    }
}
