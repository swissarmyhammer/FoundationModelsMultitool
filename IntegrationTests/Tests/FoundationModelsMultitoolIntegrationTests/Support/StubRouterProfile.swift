import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

// MARK: - A profile over stub models
//
// `RouterDiscoverySeamsTests` needs real Router handles — a `RoutedLLM` and
// a `RoutedEmbedder` — and must load no model. Router publishes every seam a
// resolve needs, thus this file resolves a profile through
// `LiveRouterFixture.makeRouter` over a loader that downloads nothing and
// loads containers that generate nothing:
//
//   StubModelLoader (ModelLoader) -> StubLLMContainer (LoadedLLMContainer)
//     -> StubSessionBackend (LanguageModelSessionBackend)
//
// and `StubEmbeddingContainer` for the embedding slot. The sizing metadata
// comes from `SizedMetadataSource`, so no resolve reads the network.

/// A metadata source that gives the sizing metadata of one small model for
/// each repo: a `config.json` with the fields that Router reads, and a tree
/// with one weights file.
struct SizedMetadataSource: MetadataSource {
    /// The `config.json` of the small model.
    private static let configJSON = """
        {"num_hidden_layers":4,"num_attention_heads":4,\
        "num_key_value_heads":4,"head_dim":32,"hidden_size":128,\
        "max_position_embeddings":4096}
        """

    /// The tree listing of the small model: one weights file.
    private static let treeJSON = """
        [{"type":"file","path":"model.safetensors","size":4096000}]
        """

    func fetchRawMetadata(repo: String, revision: String?) async throws -> RawRepoMetadata {
        RawRepoMetadata(configJSON: Data(Self.configJSON.utf8), treeJSON: Data(Self.treeJSON.utf8))
    }
}

/// A session backend that generates nothing: each response is one fixed
/// text.
///
/// The seam tests make sessions and read their type. No test sends a prompt
/// through one, so the text only has to be a valid response.
///
/// The class has no stored properties. Thus the compiler checks its plain
/// `Sendable` conformance, and the class needs no lock.
final class StubSessionBackend: LanguageModelSessionBackend, Sendable {
    /// The text of each response.
    private static let answer = "stub"

    func respond(to prompt: String, maxTokens: Int?) async throws -> String {
        Self.answer
    }

    func respond(
        to prompt: String, following grammar: Grammar, maxTokens: Int?
    ) async throws -> String {
        Self.answer
    }

    func streamResponse(to prompt: String, maxTokens: Int?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Self.answer)
            continuation.finish()
        }
    }

    func makeFork() -> any LanguageModelSessionBackend {
        StubSessionBackend()
    }

    func transcriptEntries() -> [Transcript.Entry] { [] }

    func usageTokenCounts() -> (input: Int, output: Int)? { nil }
}

/// The ``TokenCounter`` of ``StubLLMContainer``: one token per word.
///
/// Router asks a generation container for a counter. The stub model has no
/// tokenizer, thus a word — one run of characters between whitespace — is
/// one token.
struct StubWordTokenCounter: TokenCounter {
    func count(_ text: String) -> Int {
        Self.words(of: text).count
    }

    func count(_ transcript: Transcript) throws -> Int {
        transcript.reduce(0) { $0 + count(String(describing: $1)) }
    }

    func prefix(of text: String, tokens limit: Int) -> String {
        guard count(text) > limit else { return text }
        return Self.words(of: text).prefix(max(limit, 0)).joined(separator: " ")
    }

    /// The runs of characters between whitespace in `text`.
    private static func words(of text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }
}

/// A resident generation model that hands every session a
/// ``StubSessionBackend``.
struct StubLLMContainer: LoadedLLMContainer {
    let tokenCounter: any TokenCounter = StubWordTokenCounter()

    func makeSession(instructions: String?) -> any LanguageModelSessionBackend {
        StubSessionBackend()
    }

    func makeSession(transcript: Transcript) -> any LanguageModelSessionBackend {
        StubSessionBackend()
    }
}

/// An embedding model that answers one constant vector for each text.
struct StubEmbeddingContainer: LoadedEmbeddingContainer {
    /// The value of each component of each vector.
    private static let component: Float = 0.5

    let dimension = 8

    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in [Float](repeating: Self.component, count: dimension) }
    }
}

/// A loader that downloads nothing and loads the stub containers.
struct StubModelLoader: ModelLoader {
    /// The progress each load reports: the whole of a one-byte download.
    private static let completeDownload = DownloadProgress(bytesDownloaded: 1, bytesTotal: 1)

    func loadLLM(
        ref: ModelRef,
        slot: ModelSlot,
        context: Int,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedLLMContainer {
        reporting(Self.completeDownload)
        return StubLLMContainer()
    }

    func loadEmbedder(
        ref: ModelRef,
        slot: ModelSlot,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedEmbeddingContainer {
        reporting(Self.completeDownload)
        return StubEmbeddingContainer()
    }

    func preload(container: any LoadedModelContainer) async throws {}
}

/// The model reference of the `standard` slot of the stub profile.
let stubStandardModel: ModelRef = "stub/standard"

/// The model reference of the `flash` slot of the stub profile.
let stubFlashModel: ModelRef = "stub/flash"

/// The model reference of the `embedding` slot of the stub profile, when a
/// test gives none of its own.
let stubEmbeddingModel: ModelRef = "stub/embedding"

/// Resolves the stub profile on a router over ``StubModelLoader``.
///
/// The `standard` and `flash` handles vend sessions over
/// ``StubSessionBackend``, and the `embedding` handle answers
/// ``StubEmbeddingContainer``'s constant vector. No resolve loads a model or
/// reads the network.
///
/// - Parameters:
///   - embeddingModel: The model reference of the `embedding` slot. A test
///     that names a real model here must also give its own `pool`, so that
///     no stub container stays in `ModelPool.shared` under a real key.
///   - pool: The model pool the router resolves into. The default is
///     `ModelPool.shared`, the pool of the process.
/// - Returns: The resolved profile.
/// - Throws: Whatever resolving the profile throws.
func makeStubProfile(
    embeddingModel: ModelRef = stubEmbeddingModel,
    pool: ModelPool = .shared
) async throws -> LanguageModelProfile {
    let router = LiveRouterFixture.makeRouter(
        recordingsDir: LiveRouterFixture.makeTempDir(),
        loader: StubModelLoader(),
        metadataSource: SizedMetadataSource(),
        pool: pool
    )
    return try await router.resolve(
        profile: ProfileDefinition(
            name: "multitool-stub",
            description: "Stub models for the tests of the Router discovery seams.",
            standard: [stubStandardModel],
            flash: [stubFlashModel],
            embedding: [embeddingModel],
            context: nil
        ),
        reporting: ResolutionProgress()
    )
}
