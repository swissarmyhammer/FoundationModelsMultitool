import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// A Router `RoutedEmbedder` presented to the registry as a `TextEmbedding`.
///
/// The registry's searchers rank with the `TextEmbedding` seam and know
/// nothing of Router. Router's embedding handle carries the same two members
/// — a `dimension` and a batch embed — under the label `embed(texts:)`, so
/// this type forwards both and adds nothing: no batching, no error mapping.
/// It is the join between the two packages for embedding, exactly as
/// `RoutedAgentSession` is the join for a session.
///
/// `FoundationModelsCodeContext` holds an adapter of the same shape for its
/// own searcher. Each package keeps its own, as each keeps its own
/// `AgentSession` conformance: the ranker deleted its Router-specific types
/// at `34fe8d4`, and the supported route is for a consumer to conform its own.
struct RoutedTextEmbedding: TextEmbedding {
    /// The Router handle every embed travels to.
    private let embedder: RoutedEmbedder

    /// Makes the presentation over one Router embedding handle.
    ///
    /// - Parameter embedder: The resolved, resident handle to present.
    init(embedder: RoutedEmbedder) {
        self.embedder = embedder
    }

    /// The length of every vector the handle answers.
    var dimension: Int { embedder.dimension }

    /// Embeds each text into one `dimension`-length vector, in order.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: One vector per text, in the same order.
    /// - Throws: Whatever the handle throws.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await embedder.embed(texts: texts)
    }
}
