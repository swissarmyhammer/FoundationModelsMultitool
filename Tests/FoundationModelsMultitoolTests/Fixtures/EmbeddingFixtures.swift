import FoundationModelsMetadataRegistry
import os

/// A `TextEmbedding` double that records every batch it is asked to embed
/// and answers one constant vector per text.
///
/// The batches are the reading: `MetadataIndex.build` and
/// `MetadataSearcher.update(items:)` embed a catalog as ONE batch of every
/// rendered block, and a search embeds the query as a batch of one. So the
/// recorded batches say what was embedded, in what grouping, and how many
/// times — which is what a test of the embed catch-up asserts on.
///
/// `final class ... Sendable` for the same reason as `ScriptedAgentSession`:
/// `embed(_:)` records across `await` boundaries, behind an
/// `OSAllocatedUnfairLock`.
final class RecordingEmbedder: TextEmbedding, Sendable {
    /// The length of every vector this embedder answers. Any small positive
    /// length serves: cosine over equal constant vectors is `1` whatever it is.
    private static let vectorLength = 4

    /// The value every component of every answered vector carries.
    private static let component: Float = 1

    /// Every batch `embed(_:)` was handed, in call order.
    private let batchesBox = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    /// The length of every vector this embedder answers.
    let dimension = RecordingEmbedder.vectorLength

    /// Creates an embedder that has embedded nothing yet.
    init() {}

    /// Every batch `embed(_:)` was handed, in call order.
    var batches: [[String]] { batchesBox.withLock { $0 } }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        batchesBox.withLock { $0.append(texts) }
        return texts.map { _ in [Float](repeating: Self.component, count: Self.vectorLength) }
    }
}
