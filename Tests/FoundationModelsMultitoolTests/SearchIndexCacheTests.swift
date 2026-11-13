// `SearchIndexCacheTests` — each session over an equal catalog uses one
// search index, built one time.
//
// The defect that `sample` measured: each ACPAgent `session/new` built the
// search index of the catalog two times, one time for the hint searcher and
// one time for the discovery searcher. Each test here gives a cache of its
// own, so no other test changes the count of builds.

import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("SearchIndexCacheTests")
struct SearchIndexCacheTests {

    /// The task that each search of these tests asks for.
    private static let task = "trip cities"

    /// A registry over `CitiesTool` and `TempTool`, in open mode, thus with
    /// `searchTools` discovery.
    ///
    /// - Returns: the registry.
    /// - Throws: what the builder throws.
    private static func makeRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder(mode: .open).addTool(CitiesTool()).addTool(TempTool()).buildRegistry()
    }

    /// The `searchTools` tool of one composed session.
    ///
    /// - Parameter tools: the tools of the session.
    /// - Returns: the `searchTools` tool.
    /// - Throws: when the session has no `searchTools` tool.
    private static func searchTools(in tools: [any Tool]) throws -> SearchToolsTool {
        try #require(tools.compactMap { $0 as? SearchToolsTool }.first)
    }

    @Test("one session builds its index one time for both searchers")
    func oneSessionBuildsTheIndexOneTime() throws {
        let cache = SearchIndexCache()
        let registry = try Self.makeRegistry()

        let session = try registry.makeSessionToolsAndStaging(
            selection: nil, embedder: nil, sampleModel: nil, indexCache: cache)

        #expect(try Self.searchTools(in: session.tools).name == "searchTools")
        #expect(cache.builds == 1)
    }

    @Test("two sessions with the same tool set build the index one time, and both search")
    func twoSessionsWithTheSameToolSetBuildTheIndexOneTime() async throws {
        let cache = SearchIndexCache()

        let first = try Self.makeRegistry().makeSessionToolsAndStaging(
            selection: nil, embedder: nil, sampleModel: nil, indexCache: cache)
        let second = try Self.makeRegistry().makeSessionToolsAndStaging(
            selection: nil, embedder: nil, sampleModel: nil, indexCache: cache)

        #expect(cache.builds == 1)
        let block = try #require(try Self.makeRegistry().surface.entries.first { $0.path == "getCities" }).block
        for session in [first, second] {
            let feedback = try await Self.searchTools(in: session.tools)
                .call(arguments: SearchToolsArguments(task: Self.task))
            #expect(feedback.contains(block))
        }
    }

    @Test("a session with a different tool set builds an index of its own")
    func aDifferentToolSetBuildsItsOwnIndex() throws {
        let cache = SearchIndexCache()
        _ = try Self.makeRegistry().makeSessionToolsAndStaging(
            selection: nil, embedder: nil, sampleModel: nil, indexCache: cache)
        _ = try MultiTool.Builder(mode: .open).addTool(CitiesTool()).buildRegistry()
            .makeSessionToolsAndStaging(selection: nil, embedder: nil, sampleModel: nil, indexCache: cache)

        #expect(cache.builds == 2)
    }

    @Test("the cache keeps only the catalogs that were used last")
    func theCacheKeepsOnlyTheCatalogsUsedLast() throws {
        let cache = SearchIndexCache(capacity: 1)
        let both = try Self.makeRegistry().surface.entries
        let cities = try MultiTool.Builder(mode: .open).addTool(CitiesTool()).buildRegistry().surface.entries

        _ = cache.index(for: both)
        _ = cache.index(for: both)
        #expect(cache.builds == 1)
        _ = cache.index(for: cities)
        _ = cache.index(for: both)
        #expect(cache.builds == 3)
    }
}
