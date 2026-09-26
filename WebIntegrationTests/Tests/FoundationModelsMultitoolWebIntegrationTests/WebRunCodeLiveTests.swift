import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The live test of the snippet of web.md § "Goal", through a real
/// `MultiTool` and with no model (web.md § "Testing", Level 2, the
/// `WebRunCodeLiveTests` row).
///
/// The registry comes from `MultiTool.Builder().withWeb(configuration:
/// .keyless, sessionConfiguration:)`, the public mount of a host, with the
/// short timeouts of ``LiveSearch/makeShortTimeoutConfiguration()``. The
/// snippet goes through `MultiTool.call(arguments:)`: the JSC interpreter, the
/// `tools.web` bindings, and `ToolInvoker`. The search goes to the real
/// keyless providers, and each fetch goes to a real page. A test does not
/// retry.
///
/// **The DuckDuckGo challenge page (web.md, decided 2026-09-26).** The chain
/// of `.keyless` tries `braveHTML` first. When Brave gives hits, the chain
/// does not ask DuckDuckGo. The test does not assert which keyless provider
/// gave the hits, and it does not read `notes`. Thus a DuckDuckGo challenge
/// page alone cannot fail this test. A challenge page can only have an effect
/// after Brave failed, and then the failure of Brave is the failure that the
/// test reports.
@Suite(
    "Live: the search-then-fetch snippet of web.md runs through runCode",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct WebRunCodeLiveTests {
    /// The snippet of web.md § "Goal", word for word.
    private static let goalSnippet = """
        const hits = await tools.web.search({ query: "swift structured concurrency" });
        const pages = await Promise.all(
          hits.results.slice(0, 3).map(r => tools.web.fetch({ url: r.url, maxCharacters: 4000 })));
        return pages.map(p => ({ url: p.url, title: p.title, head: p.content.slice(0, 400) }));
        """

    /// The number of pages that the snippet can return: at least one hit,
    /// and at most the three hits of its `slice`.
    private static let pageCountRange = 1...3

    /// The value that the goal snippet returns for each page.
    private struct PageHead: Decodable {
        /// The final URL of the page.
        let url: String

        /// The title of the page, or `nil` when the page has no title.
        let title: String?

        /// The first characters of the content of the page.
        let head: String
    }

    @Test("the goal snippet returns 1 to 3 pages, each with a title and content")
    func goalSnippetReturnsPages() async throws {
        let registry = try MultiTool.Builder()
            .withWeb(configuration: .keyless, sessionConfiguration: LiveSearch.makeShortTimeoutConfiguration())
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.goalSnippet))

        let heads = try Self.decodedHeads(from: output)
        #expect(Self.pageCountRange.contains(heads.count), "the snippet returned: \(output)")
        for page in heads {
            #expect(page.title?.isEmpty == false, "the page \(page.url) has no title")
            #expect(!page.head.isEmpty, "the page \(page.url) has no content")
        }
    }

    /// Decodes the JSON value that the goal snippet returned.
    ///
    /// - Parameter output: The rendered output of the run.
    /// - Returns: The value of each page.
    /// - Throws: When the output is not the JSON text of the pages. The
    ///   failure record holds the output.
    private static func decodedHeads(from output: String) throws -> [PageHead] {
        do {
            return try JSONDecoder().decode([PageHead].self, from: Data(output.utf8))
        } catch {
            Issue.record("the output did not decode as the pages: \(output)")
            throw error
        }
    }
}
