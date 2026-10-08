import FoundationModelsExtras
import os

/// A `PooledEmbedding` double that records every batch it is asked to embed
/// and answers one constant vector per text.
///
/// The batches are the reading: the registry's first-search catch-up embeds
/// a catalog as ONE batch of the embedded text of each entry, and a search
/// embeds the query as a batch of one. So the recorded batches say what was
/// embedded, in what grouping, and how many times — which is what a test of
/// the embed catch-up asserts on.
///
/// `final class ... Sendable` because `embed(texts:)` records across `await`
/// boundaries, behind an `OSAllocatedUnfairLock`.
final class RecordingEmbedder: PooledEmbedding, Sendable {
    /// The error a failing `RecordingEmbedder` throws out of every
    /// `embed(texts:)` call — the transient model failure a host sees when the
    /// embedding model is resident but the call did not complete.
    struct Failure: Error {}

    /// The length of every vector this embedder answers. Any small positive
    /// length serves: cosine over equal constant vectors is `1` whatever it is.
    private static let vectorLength = 4

    /// The value every component of every answered vector carries.
    private static let component: Float = 1

    /// Every batch `embed(texts:)` was handed, in call order.
    private let batchesBox = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    /// Whether `embed(texts:)` records its batch and then throws ``Failure``.
    private let alwaysFails: Bool

    /// Creates an embedder that has embedded nothing yet.
    ///
    /// - Parameter alwaysFails: `true` to record each batch and then throw
    ///   ``Failure`` instead of answering vectors. Defaults to `false`, the
    ///   embedder that always answers.
    init(alwaysFails: Bool = false) {
        self.alwaysFails = alwaysFails
    }

    /// Every batch `embed(texts:)` was handed, in call order.
    var batches: [[String]] { batchesBox.withLock { $0 } }

    func embed(texts: [String]) async throws -> [[Float]] {
        batchesBox.withLock { $0.append(texts) }
        if alwaysFails { throw Failure() }
        return texts.map { _ in [Float](repeating: Self.component, count: Self.vectorLength) }
    }
}
