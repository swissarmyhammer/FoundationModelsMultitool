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
// An embedder is the same embedder when it conforms to `IdentifiedEmbedding`
// and gives the same owner object. An embedder that does not conform shares
// its embed only inside one bundle.
//
// **The cache keeps no embedder alive.** An embedder can hold a loaded model,
// and a model can use GBs of memory. Thus a cached embed slot holds only weak
// references: to the owner, to the embedder, and to the shared embed. The
// searchers of each session hold the shared embed, and through it the
// embedder. When the last session that uses an embed ends, the shared embed
// and the embedder go, and the slot is empty. The cache drops each empty
// slot. A weak reference to the owner also makes the key safe: a released
// owner never matches a new object, also when the new object gets the same
// address.
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
/// protocol. Then each session with an equal catalog and the same owner
/// shares one catalog embed, while one of these sessions is open. An
/// embedder that does not conform shares its catalog embed only between the
/// two searchers of one bundle.
public protocol IdentifiedEmbedding: PooledEmbedding {
    /// The object that identifies this embedder, for example the shared
    /// model handle that it wraps. Two embedders with the same owner object
    /// must give the same vector for the same text. The cache holds the
    /// owner with a weak reference only, so it does not keep the owner, or
    /// the model that the owner holds, alive.
    var embeddingOwner: any AnyObject & Sendable { get }
}

/// A process-wide cache of built search indexes and shared catalog embeds,
/// keyed by the catalog entries (and the embedder for an embed).
///
/// ``index(for:)`` gives the index of a catalog. It builds the index only
/// when the cache holds no index for an equal catalog. The cache keeps the
/// indexes of the ``capacity`` catalogs that were used last. Thus a host that
/// changes its tool set many times does not keep each old index.
///
/// ``sharedEmbedding(for:embedder:)`` gives the shared catalog embed of a
/// catalog and an embedder. The cache holds each shared embed with a weak
/// reference only, so an embed lives only while a session uses it.
///
/// The build runs under the lock. Thus two sessions that start at the same
/// time with the same catalog build the index one time, not two times.
///
/// A host uses ``shared``. A test gives a cache of its own to
/// `MultiTool.Registry.makeSessionToolsAndStaging(selection:embedder:sampleModel:indexCache:)`,
/// so that no other test changes what the cache holds, and reads
/// ``builds`` and ``sharedEmbeddings``.
public final class SearchIndexCache: Sendable {
    /// The cache that each bundle and each `searchTools` tool uses when the
    /// caller gives no other cache.
    public static let shared = SearchIndexCache()

    /// The default number of catalog indexes that a cache keeps.
    public static let defaultCapacity = 8

    /// One cached catalog and its built index.
    private struct Slot: Sendable {
        /// The catalog entries, in the order that the index was built from.
        let entries: [APISurface.Entry]

        /// The index built from ``entries``.
        let index: MetadataIndex<APISurface.Entry>
    }

    /// One cached shared catalog embed. Each reference is weak, so the slot
    /// keeps nothing alive.
    private struct EmbeddingSlot: Sendable {
        /// The catalog entries of the embed.
        let entries: [APISurface.Entry]

        /// The owner object of the embedder of the embed.
        let owner: WeakReference<any AnyObject & Sendable>

        /// The embedder that records whether an embed failed.
        let embedder: WeakReference<FailureObservingEmbedding>

        /// The shared catalog embed.
        let shared: WeakReference<SharedCatalogEmbedding<APISurface.Entry>>

        /// Whether the slot can give its embed: the owner and the embed
        /// exist, and no embed of the embedder failed.
        var isLive: Bool {
            guard owner.object != nil, shared.object != nil, let embedder = embedder.object else { return false }
            return !embedder.hasFailed
        }
    }

    /// What the lock guards.
    private struct State: Sendable {
        /// The cached catalogs. The catalog that was used last is first.
        var slots: [Slot] = []

        /// The cached shared catalog embeds that a session still uses.
        var embeddingSlots: [EmbeddingSlot] = []

        /// The number of indexes that this cache built.
        var builds = 0

        /// The number of shared catalog embeds that this cache made.
        var sharedEmbeddings = 0
    }

    /// The number of catalog indexes that this cache keeps.
    public let capacity: Int

    /// The guarded state.
    private let state = Mutex(State())

    /// Creates an empty cache.
    ///
    /// - Parameter capacity: the number of catalog indexes to keep. A value
    ///   less than one keeps one index.
    public init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// The number of indexes that this cache built. A test reads it to count
    /// the builds.
    public var builds: Int {
        state.withLock { $0.builds }
    }

    /// The number of shared catalog embeds that this cache made. A test
    /// reads it to count them: two sessions that share one embed make one.
    public var sharedEmbeddings: Int {
        state.withLock { $0.sharedEmbeddings }
    }

    /// The number of shared catalog embeds that a session still uses. A
    /// test reads it to see that the cache keeps no embed after the
    /// sessions end.
    public var liveSharedEmbeddings: Int {
        state.withLock { state in
            state.embeddingSlots.removeAll { !$0.isLive }
            return state.embeddingSlots.count
        }
    }

    /// The shared catalog embed of `entries` with `embedder`: the embed of
    /// an equal catalog and the same embedder that a session still uses, or
    /// a new embed.
    ///
    /// The cache records a new embed only when `embedder` has an owner (see
    /// ``IdentifiedEmbedding``). It drops an embed after an embed of its
    /// embedder failed, and makes a new one.
    ///
    /// - Parameters:
    ///   - entries: the catalog entries.
    ///   - embedder: the embedder of the catalog and of each query.
    /// - Returns: the shared catalog embed. The caller must keep it: the
    ///   cache does not.
    func sharedEmbedding(
        for entries: [APISurface.Entry], embedder: any PooledEmbedding
    ) -> SharedCatalogEmbedding<APISurface.Entry> {
        let index = index(for: entries)
        let owner = Self.owner(of: embedder)
        return state.withLock { state in
            state.embeddingSlots.removeAll { !$0.isLive }
            if let owner,
                let slot = state.embeddingSlots.first(where: {
                    $0.owner.object === owner && $0.entries == entries
                }),
                let shared = slot.shared.object
            {
                return shared
            }
            let observing = FailureObservingEmbedding(base: embedder)
            let shared = SharedCatalogEmbedding(index: index, embedder: observing)
            state.sharedEmbeddings += 1
            if let owner {
                state.embeddingSlots.append(
                    EmbeddingSlot(
                        entries: entries, owner: WeakReference(owner), embedder: WeakReference(observing),
                        shared: WeakReference(shared)))
            }
            return shared
        }
    }

    /// The owner object of `embedder`, or `nil` when it has none.
    ///
    /// - Parameter embedder: the embedder.
    /// - Returns: the ``IdentifiedEmbedding/embeddingOwner`` of the
    ///   embedder, or `nil` when the embedder does not conform.
    private static func owner(of embedder: any PooledEmbedding) -> (any AnyObject & Sendable)? {
        (embedder as? any IdentifiedEmbedding)?.embeddingOwner
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

/// A weak reference to an object, which the slots of ``SearchIndexCache``
/// hold so that the cache keeps nothing alive.
///
/// The reference is set one time, in `init`, and the object is `Sendable`,
/// thus the reference is `Sendable`.
struct WeakReference<Object: AnyObject & Sendable>: Sendable {
    /// The object, or `nil` after it was released.
    weak let object: Object?

    /// Creates a weak reference to `object`.
    ///
    /// - Parameter object: the object to refer to.
    init(_ object: Object) {
        self.object = object
    }
}
