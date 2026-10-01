import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The live test of the snippet of web.md § "Goal", through a real
/// `MultiTool` and with no model (web.md § "Testing", Level 2, the
/// `WebRunCodeLiveTests` row).
///
/// The registry comes from `MultiTool.Builder().withWeb(configuration:
/// .keyless, sessionConfiguration:)`, the public mount of a host, with the
/// short timeouts of ``LiveSearch/makeSessionConfiguration()``. The
/// snippet goes through `MultiTool.call(arguments:)`: the JSC interpreter, the
/// `tools.web` bindings, and `ToolInvoker`. The search goes to the real
/// keyless providers, and each fetch goes to a real page. A test does not
/// retry.
///
/// **A blocked provider (``BlockedProviderRule``, web.md).** The chain of
/// `.keyless` tries `braveHTML`, then `duckDuckGoHTML`, and goes to the next
/// provider after a block. The test does not assert which keyless provider
/// gave the hits, and it does not read `notes`. Thus one blocked provider
/// does not fail this test when the other provider gives results. When no
/// provider gives results, the snippet gets a correction and not hits, and
/// the test fails. The snippet goes through the chain of a real `MultiTool`,
/// thus the chain itself applies the rule, and the test sends no second
/// search.
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

    @Test("the goal snippet returns 1 to 3 pages, each with a title and content")
    func goalSnippetReturnsPages() async throws {
        let registry = try MultiTool.Builder()
            .withWeb(configuration: .keyless, sessionConfiguration: LiveSearch.makeSessionConfiguration())
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.goalSnippet))

        let heads = try RunOutput.decoded([WebPageHead].self, from: output)
        #expect(Self.pageCountRange.contains(heads.count), "the snippet returned: \(output)")
        for page in heads {
            #expect(page.title?.isEmpty == false, "the page \(page.url) has no title")
            #expect(!page.head.isEmpty, "the page \(page.url) has no content")
        }
    }
}
