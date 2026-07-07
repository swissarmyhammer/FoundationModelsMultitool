import FoundationModels
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `APISurface.Entry`'s `SearchableMetadata` conformance (task
/// p44m84d): the rendered tool catalog becomes searchable by the registry
/// once `entry.id`/`entry.renderBlock()` line up with `path`/`block`, the
/// same identity the plan's "conform, don't wrap" approach calls for.
@Suite("APISurfaceSearchableMetadata")
struct APISurfaceSearchableMetadataTests {
    @Test("a standalone entry's id and renderBlock() are its path and block")
    func standaloneEntryIdAndRenderBlockMatchPathAndBlock() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()
        let entry = try #require(surface.entries.first)

        #expect(entry.group == nil)
        #expect(entry.id == entry.path)
        #expect(entry.renderBlock() == entry.block)
    }

    @Test("a grouped entry's id and renderBlock() are its path and block")
    func groupedEntryIdAndRenderBlockMatchPathAndBlock() throws {
        let surface = try MultiTool.Builder()
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()
        let entry = try #require(surface.entries.first)

        #expect(entry.group == "github")
        #expect(entry.id == entry.path)
        #expect(entry.renderBlock() == entry.block)
    }

    @Test("a MetadataSearcher over a real built surface ranks the expected tool first for a keyword query")
    func retrievalSearchRanksExpectedToolFirst() async throws {
        let surface = try MultiTool.Builder()
            .addTool(WeatherTool())
            .addTool(TripCitiesTool())
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()

        let searcher = MetadataSearcher(items: surface.entries, mode: .retrieval)
        let matches = try await searcher.search(intent: "current weather conditions for a city", limit: 3)

        #expect(matches.first?.id == "weather")
    }
}
