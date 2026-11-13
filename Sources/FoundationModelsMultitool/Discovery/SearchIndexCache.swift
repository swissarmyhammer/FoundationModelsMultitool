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
// one built index can go to each searcher: each searcher keeps its own copy,
// and embeds into its own copy at its first search.

import FoundationModelsMetadataRegistry
import Synchronization

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

    /// What the lock guards.
    private struct State: Sendable {
        /// The cached catalogs. The catalog that was used last is first.
        var slots: [Slot] = []

        /// The number of indexes that this cache built.
        var builds = 0
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
            if let position = state.slots.firstIndex(where: { $0.entries == entries }) {
                let slot = state.slots.remove(at: position)
                state.slots.insert(slot, at: 0)
                return slot.index
            }
            let index = MetadataIndex(items: entries)
            state.builds += 1
            state.slots.insert(Slot(entries: entries, index: index), at: 0)
            if state.slots.count > capacity {
                state.slots.removeLast(state.slots.count - capacity)
            }
            return index
        }
    }
}
