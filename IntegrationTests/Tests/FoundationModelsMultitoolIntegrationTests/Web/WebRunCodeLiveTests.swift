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
/// provider after a block. When each provider blocks the search, the search
/// gives a correction and no hit. The goal snippet of web.md then returns
/// `[]`, and the correction does not reach the output. Thus the snippet of
/// this test is the goal snippet with one added line: a search with a
/// correction returns the search itself. The output is then the block report,
/// and the rule checks it. The test does not decode that output as pages.
@Suite(
    "Live: the search-then-fetch snippet of web.md runs through runCode",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct WebRunCodeLiveTests {
    /// The snippet of web.md § "Goal", word for word, with one added line
    /// after the search: `if (hits.correction) return hits;`.
    private static let goalSnippet = """
        const hits = await tools.web.search({ query: "swift structured concurrency" });
        if (hits.correction) return hits;
        const pages = await Promise.all(
          hits.results.slice(0, 3).map(r => tools.web.fetch({ url: r.url, maxCharacters: 4000 })));
        return pages.map(p => ({ url: p.url, title: p.title, head: p.content.slice(0, 400) }));
        """

    /// The number of pages that the snippet can return: at least one hit,
    /// and at most the three hits of its `slice`.
    private static let pageCountRange = 1...3

    @Test("the goal snippet returns 1 to 3 pages, each with a title and content, or the search of a recognized block")
    func goalSnippetReturnsPages() async throws {
        let registry = try MultiTool.Builder()
            .withWeb(configuration: .keyless, sessionConfiguration: LiveSearch.makeSessionConfiguration())
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.goalSnippet))

        switch try RunOutput.decoded(GoalSnippetOutput.self, from: output) {
        case .pages(let heads):
            Self.expectPages(heads, output: output)
        case .search(let search):
            BlockedProviderRule.expectResultsOrBlock(
                search.result, providers: WebConfiguration.keyless.providers
            ) {
                Issue.record("the snippet returned the search, and the search has hits: \(output)")
            }
        }
    }

    /// Checks the pages of the snippet: 1 to 3 pages, each with a title and
    /// content.
    ///
    /// - Parameters:
    ///   - heads: The pages that the snippet returned.
    ///   - output: The rendered output of the snippet, for the failure
    ///     comment.
    private static func expectPages(_ heads: [WebPageHead], output: String) {
        #expect(pageCountRange.contains(heads.count), "the snippet returned: \(output)")
        for page in heads {
            #expect(page.title?.isEmpty == false, "the page \(page.url) has no title")
            #expect(!page.head.isEmpty, "the page \(page.url) has no content")
        }
    }
}

/// The output of the snippet of ``WebRunCodeLiveTests``: the pages, or the
/// search when the search has a correction.
private enum GoalSnippetOutput: Decodable {
    /// The pages of a search that gave hits.
    case pages([WebPageHead])

    /// The search, which the snippet returns when it has a correction.
    case search(SnippetSearch)

    /// Decodes an array as the pages, and an object as the search.
    ///
    /// - Parameter decoder: The decoder of the output.
    /// - Throws: When the output is neither form.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let pages = try? container.decode([WebPageHead].self) {
            self = .pages(pages)
        } else {
            self = .search(try container.decode(SnippetSearch.self))
        }
    }
}

/// The result of `tools.web.search` as the snippet returns it, with the
/// fields of `SearchResult`.
private struct SnippetSearch: Decodable {
    /// The provider that gave the hits. Empty on a correction.
    let provider: String

    /// The hits.
    let results: [SnippetHit]

    /// The notes, or `nil` when there are none.
    let notes: [String]?

    /// The correction, or `nil` when the hits stand.
    let correction: String?

    /// The same facts as the `SearchResult` that ``BlockedProviderRule``
    /// reads.
    var result: SearchResult {
        SearchResult(provider: provider, results: results.map(\.hit), notes: notes, correction: correction)
    }
}

/// One hit of ``SnippetSearch``, with the fields of `WebHit`.
private struct SnippetHit: Decodable {
    /// The position of the hit in the results, from 1.
    let rank: Int

    /// The title of the page.
    let title: String

    /// The URL of the page.
    let url: String

    /// A short text from the page.
    let snippet: String

    /// The same facts as a `WebHit`.
    var hit: WebHit {
        WebHit(rank: rank, title: title, url: url, snippet: snippet)
    }
}
