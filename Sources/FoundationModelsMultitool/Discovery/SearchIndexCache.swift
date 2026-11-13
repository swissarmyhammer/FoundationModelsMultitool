// `SearchIndexCache` — one search index for each catalog, shared by each
// searcher and each session that searches the same catalog.
//
// The problem that `sample` measured in the TestudoApp test process: each
// ACPAgent `session/new` built the search index of the tool catalog two
// times. `RegistryBundle.init` built one for the hint searcher, and
// `SearchToolsTool.makeSearcher` built one more for the discovery searcher.
// Each build renders, tokenizes and trigrams each entry
// (`MetadataIndex.init`), about 0.4 s of CPU for each session. The catalog is
// the same for each session of the same mode and selection.
//
// `MetadataIndex` is a value with no embedding in it when it is built. Thus
// one built index can go to each searcher: each searcher keeps its own copy.
//
// **The catalog embed.** With an embedder, each searcher also embedded the
// whole catalog at its first search. Thus one bundle embedded it two times,
// and each session embedded it again. The cache also keeps one
// `SharedCatalogEmbedding` (FoundationModelsMetadataRegistry) for each catalog
// and embedder. Both searchers of a bundle, and each bundle with an equal
// catalog and the same embedder, share its one catalog embed.
//
// An embedder is the same embedder when it is the same object (a class
// instance), or when it conforms to `IdentifiedEmbedding` and gives an equal
// identity. The cache keeps a strong reference to the embedder of each slot,
// thus the identity of an object cannot go to a new object while the slot
// exists. An embedder with no identity shares its embed only inside one
// bundle.
//
// A shared catalog embed that failed does not embed again. Thus the cache
// drops a slot after an embed of its embedder failed, and the next bundle
// makes a new shared embed that tries again.

import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Synchronization

/// An embedder that tells the search index cache which embedders are the
/// same.
///
/// A host that makes a new embedder value for each session (for example, a
/// struct that wraps a shared model handle) conforms the value to this
/// protocol. Then each session with an equal catalog shares one catalog
/// embed. A class instance does not need this protocol: the cache uses the
/// identity of the object.
public protocol IdentifiedEmbedding: PooledEmbedding {
    /// The identity of this embedder: the `ObjectIdentifier` of an object
    /// that this embedder holds, for example the shared model handle. Two
    /// embedders with an equal identity must give the same vector for the
    /// same text. The cache keeps this embedder, and thus the object, while
    /// it keeps the identity. Thus the identity cannot go to a new object.
    var embeddingIdentity: ObjectIdentifier { get }
}

/// A process-wide cache of built search indexes, keyed by the catalog
/// entries.
///
/// ``index(for:)`` gives the index of a catalog. It builds the index only
/// when the cache holds no index for an equal catalog. The cache keeps the
/// indexes of the ``capacity`` catalogs that were used last. Thus a host that
/// changes its tool set many times does not keep each old index.
///
/// The build runs under the lock. Thus two sessions that start at the same
/// time with the same catalog build the index one time, not two times.
final class SearchIndexCache: Sendable {
    /// The cache that each bundle and each `searchTools` tool uses when the
    /// caller gives no other cache.
    static let shared = SearchIndexCache()

    /// The default number of catalogs that a cache keeps.
    static let defaultCapacity = 8

    /// One cached catalog and its built index.
    private struct Slot: Sendable {
        /// The catalog entries, in the order that the index was built from.
        let entries: [APISurface.Entry]

        /// The index built from ``entries``.
        let index: MetadataIndex<APISurface.Entry>
    }

    /// One cached shared catalog embed.
    private struct EmbeddingSlot: Sendable {
        /// The catalog entries of the embed.
        let entries: [APISurface.Entry]

        /// The identity of the embedder of the embed.
        let identity: ObjectIdentifier

        /// The embedder that records whether an embed failed.
        let embedder: FailureObservingEmbedding

        /// The shared catalog embed.
        let shared: SharedCatalogEmbedding<APISurface.Entry>
    }

    /// What the lock guards.
    private struct State: Sendable {
        /// The cached catalogs. The catalog that was used last is first.
        var slots: [Slot] = []

        /// The cached shared catalog embeds. The embed that was used last is
        /// first.
        var embeddingSlots: [EmbeddingSlot] = []

        /// The number of indexes that this cache built.
        var builds = 0

        /// The number of shared catalog embeds that this cache made.
        var sharedEmbeddings = 0
    }

    /// The number of catalogs that this cache keeps.
    let capacity: Int

    /// The guarded state.
    private let state = Mutex(State())

    /// Creates an empty cache.
    ///
    /// - Parameter capacity: the number of catalogs to keep. A value less
    ///   than one keeps one catalog.
    init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// The number of indexes that this cache built. A test reads it to count
    /// the builds.
    var builds: Int {
        state.withLock { $0.builds }
    }

    /// The number of shared catalog embeds that this cache made. A test
    /// reads it to count them.
    var sharedEmbeddings: Int {
        state.withLock { $0.sharedEmbeddings }
    }

    /// The shared catalog embed of `entries` with `embedder`: the cached
    /// embed of an equal catalog and the same embedder, or a new embed.
    ///
    /// The cache keeps a new embed only when `embedder` has an identity (see
    /// ``IdentifiedEmbedding``). It drops a cached embed after an embed of
    /// its embedder failed, and makes a new one.
    ///
    /// - Parameters:
    ///   - entries: the catalog entries.
    ///   - embedder: the embedder of the catalog and of each query.
    /// - Returns: the shared catalog embed.
    func sharedEmbedding(
        for entries: [APISurface.Entry], embedder: any PooledEmbedding
    ) -> SharedCatalogEmbedding<APISurface.Entry> {
        let index = index(for: entries)
        let identity = Self.identity(of: embedder)
        return state.withLock { state in
            state.embeddingSlots.removeAll { $0.embedder.hasFailed }
            if let identity,
                let slot = state.embeddingSlots.moveToFront(where: {
                    $0.identity == identity && $0.entries == entries
                })
            {
                return slot.shared
            }
            let observing = FailureObservingEmbedding(base: embedder)
            let shared = SharedCatalogEmbedding(index: index, embedder: observing)
            state.sharedEmbeddings += 1
            if let identity {
                state.embeddingSlots.insertAtFront(
                    EmbeddingSlot(entries: entries, identity: identity, embedder: observing, shared: shared),
                    keeping: capacity)
            }
            return shared
        }
    }

    /// The identity of `embedder`, or `nil` when it has none.
    ///
    /// - Parameter embedder: the embedder.
    /// - Returns: the ``IdentifiedEmbedding/embeddingIdentity`` of the
    ///   embedder, the `ObjectIdentifier` of a class instance, or `nil`.
    private static func identity(of embedder: any PooledEmbedding) -> ObjectIdentifier? {
        if let identified = embedder as? any IdentifiedEmbedding {
            return identified.embeddingIdentity
        }
        if type(of: embedder) is AnyClass {
            return ObjectIdentifier(embedder as AnyObject)
        }
        return nil
    }

    /// The search index of `entries`: the cached index of an equal catalog,
    /// or a new index that this call builds and keeps.
    ///
    /// Two catalogs are equal when they have the same entries in the same
    /// order. The order is part of the key, because the index resolves a
    /// duplicate id by the first entry.
    ///
    /// - Parameter entries: the catalog entries to index.
    /// - Returns: the index of `entries`.
    func index(for entries: [APISurface.Entry]) -> MetadataIndex<APISurface.Entry> {
        state.withLock { state in
            if let slot = state.slots.moveToFront(where: { $0.entries == entries }) {
                return slot.index
            }
            let index = MetadataIndex(items: entries)
            state.builds += 1
            state.slots.insertAtFront(Slot(entries: entries, index: index), keeping: capacity)
            return index
        }
    }
}

/// The order rule of the slots of ``SearchIndexCache``: the slot that was
/// used last is first, and the array keeps a maximum number of slots.
extension Array {
    /// Moves the first element that `isMatch` accepts to the front.
    ///
    /// - Parameter isMatch: the test of one element.
    /// - Returns: the moved element, or `nil` when no element matches.
    fileprivate mutating func moveToFront(where isMatch: (Element) -> Bool) -> Element? {
        guard let position = firstIndex(where: isMatch) else { return nil }
        let element = remove(at: position)
        insert(element, at: 0)
        return element
    }

    /// Inserts `element` at the front, then removes the elements at the end
    /// that are more than `capacity`.
    ///
    /// - Parameters:
    ///   - element: the element to insert.
    ///   - capacity: the maximum number of elements to keep.
    fileprivate mutating func insertAtFront(_ element: Element, keeping capacity: Int) {
        insert(element, at: 0)
        if count > capacity {
            removeLast(count - capacity)
        }
    }
}

/// An embedder that forwards each embed to its base embedder, and records
/// whether an embed failed.
///
/// ``SearchIndexCache`` drops a shared catalog embed after its embedder
/// failed one time. A failed shared embed does not embed again, so a new
/// shared embed must try again.
final class FailureObservingEmbedding: PooledEmbedding {
    /// The embedder that does the embeds.
    let base: any PooledEmbedding

    /// Whether an embed failed.
    private let failed = Mutex(false)

    /// Creates the embedder over `base`.
    ///
    /// - Parameter base: the embedder that does the embeds.
    init(base: any PooledEmbedding) {
        self.base = base
    }

    /// Whether an embed of this embedder failed.
    var hasFailed: Bool {
        failed.withLock { $0 }
    }

    /// Embeds `texts` with the base embedder, and records a failure.
    ///
    /// - Parameter texts: the texts to embed.
    /// - Returns: one vector for each text.
    /// - Throws: what the base embedder throws.
    func embed(texts: [String]) async throws -> [[Float]] {
        do {
            return try await base.embed(texts: texts)
        } catch {
            failed.withLock { $0 = true }
            throw error
        }
    }
}
