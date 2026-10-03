import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The live test of the snippet of web.md § "Goal", through a real
/// `MultiTool` and with no model (web.md § "Testing", Level 2, the
/// `WebRunCodeLiveTests` row).
///
/// The registry comes from `MultiTool.Builder().withWeb(configuration:
/// .keyless)`, the public mount of a host, with the default `.ephemeral`
/// session. The snippet goes through `MultiTool.call(arguments:)`: the JSC
/// interpreter, the `tools.web` bindings, and `ToolInvoker`. The search goes
/// to the real keyless providers, and each fetch goes to a real page. A test
/// does not retry.
///
/// **A blocked provider (``BlockedProviderRule``, web.md).** The chain of
/// `.keyless` tries `braveHTML`, then `duckDuckGoHTML`, and goes to the next
/// provider after a block. When each provider blocks the search, the search
/// gives a correction and no hit. The goal snippet of web.md then returns
/// `[]`, and the correction does not reach the output. Thus the snippet of
/// this test has one added line: a search with a correction returns the
/// search itself. The output is then the block report,
/// and the rule checks it. The test does not decode that output as pages.
///
/// **The pages (``FetchedPagesRule``, card `^4dfyx4q`).** The snippet also
/// returns the `correction` of each fetch, thus the test sees a failed fetch.
/// Each page must have a valid URL and a title, and its fetch must not fail.
/// At least one page must have content. A page that JavaScript draws gives
/// empty content, and it passes with those checks.
@Suite(
    "Live: the search-then-fetch snippet of web.md runs through runCode",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct WebRunCodeLiveTests {
    /// The snippet of web.md § "Goal", with two changes: one added line
    /// after the search, `if (hits.correction) return hits;`, and the
    /// `correction` of each fetch in the returned pages.
    private static let goalSnippet = """
        const hits = await tools.web.search({ query: "swift structured concurrency" });
        if (hits.correction) return hits;
        const pages = await Promise.all(
          hits.results.slice(0, 3).map(r => tools.web.fetch({ url: r.url, maxCharacters: 4000 })));
        return pages.map(p => ({
          url: p.url, title: p.title, head: p.content.slice(0, 400), correction: p.correction }));
        """

    @Test("the goal snippet returns pages with a URL and a title, one with content, or a recognized block")
    func goalSnippetReturnsPages() async throws {
        let registry = try MultiTool.Builder()
            .withWeb(configuration: .keyless)
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.goalSnippet))

        switch try RunOutput.decoded(GoalSnippetOutput.self, from: output) {
        case .pages(let heads):
            FetchedPagesRule.expectPages(heads, output: output)
        case .search(let search):
            BlockedProviderRule.expectResultsOrBlock(
                search.result, providers: WebConfiguration.keyless.providers
            ) {
                Issue.record("the snippet returned the search, and the search has hits: \(output)")
            }
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
