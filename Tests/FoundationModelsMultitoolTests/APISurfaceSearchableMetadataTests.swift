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

    /// The four pieces of text that stand only in the full block: the three
    /// JSDoc tags the renderer emits below the description, and the
    /// `declare function` line. A summary block that holds any one of them
    /// carries signature text into the selection prompt.
    private static let signatureOnlyTexts = ["@param", "@returns", "@example", "declare function"]

    /// The banner line of the `tools.github.createIssue` entry, with the
    /// newline that separates it from the text below it.
    private static let githubCreateIssueBanner = "// tools.github.createIssue\n"

    /// Builds the two-tool `github` group and returns its first entry,
    /// `tools.github.createIssue` — a grouped entry, so the banner carries a
    /// path the bare tool name does not.
    private static func githubCreateIssueEntry() throws -> APISurface.Entry {
        let surface = try MultiTool.Builder()
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()
        return try #require(surface.entries.first)
    }

    @Test("renderSummaryBlock() holds the banner and the description, and no signature text")
    func summaryBlockHoldsBannerAndDescriptionOnly() throws {
        let entry = try Self.githubCreateIssueEntry()

        let summary = entry.renderSummaryBlock()

        #expect(summary.hasPrefix(Self.githubCreateIssueBanner), "summary was: \(summary)")
        #expect(summary.contains(GithubCreateIssueTool().description), "summary was: \(summary)")
        for signatureText in Self.signatureOnlyTexts {
            #expect(!summary.contains(signatureText), "summary holds \(signatureText): \(summary)")
        }
    }

    @Test("renderBlock() stays the full block: the banner, the JSDoc tags and the declaration")
    func renderBlockStaysTheFullBlock() throws {
        let entry = try Self.githubCreateIssueEntry()

        let block = entry.renderBlock()

        #expect(block == entry.block)
        #expect(block.hasPrefix(Self.githubCreateIssueBanner), "block was: \(block)")
        for signatureText in Self.signatureOnlyTexts {
            #expect(block.contains(signatureText), "block lacks \(signatureText): \(block)")
        }
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

        #expect(matches.first?.id == "getWeather")
    }
}
