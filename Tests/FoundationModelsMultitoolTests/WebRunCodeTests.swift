// `WebRunCodeTests` — the two web verbs, driven end to end through `runCode`
// (web.md § "Goal" and the `WebRunCodeTests` row of § "Testing / Level 1").
//
// The suites `WebVerbArgumentTests`, `WebFetcherTests`, and the provider
// suites prove each part alone, through direct calls. This suite proves the
// two verbs through the code-mode surface instead: each test runs JavaScript
// through `MultiTool.call(arguments:)`, which goes through the JSC interpreter
// and `ToolInvoker`. The shape is `FilesCrossOpFlowTests`.
//
// Each test makes its own `WebRun`: a `WebStub` answers each request, and the
// guard uses `PublicHostResolver`. Thus no request and no DNS lookup goes to
// the network. `WebRun.runSnippet(_:)` examines each output for the test key.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The web verbs as one session, each flow through `runCode` snippets over a
/// stub session.
///
/// The flows: the search-then-fetch snippet of web.md § "Goal"; a
/// `Promise.all` over three fetches; a guard refusal and a bad argument that
/// come back as values; and a keyed search whose key is in no output.
@Suite("WebRunCodeTests")
struct WebRunCodeTests {

    // MARK: - The constants of the snippets

    /// The number of hits that the stub search gives in the goal flow. It is
    /// more than ``fetchedPageCount``, thus the `slice` of the snippet has an
    /// effect.
    private static let searchHitCount = 4

    /// The number of pages that the goal snippet fetches, and the number of
    /// fetches in the `Promise.all` flow.
    private static let fetchedPageCount = 3

    /// The window size of each fetch of the goal snippet.
    private static let maxCharacters = 4000

    /// The number of characters of each content head that the goal snippet
    /// returns.
    private static let headLength = 400

    /// A URL on the blocklist of the guard.
    private static let blockedURL = "http://127.0.0.1/"

    /// The correction of the guard for ``blockedURL``.
    private static let blockedCorrection = "The address is not allowed: the host 127.0.0.1 is on the blocklist."

    /// A URL whose scheme is not `http` or `https`.
    private static let badSchemeURL = "ftp://x"

    /// The correction of the `fetch` verb for ``badSchemeURL``.
    private static let badSchemeCorrection = "The `url` parameter must be an absolute http or https URL: ftp://x"

    /// The text that the correction snippet returns when a call throws. A
    /// test that reads this text in the output fails.
    private static let thrownMarker = "a web call threw"

    // MARK: - Helpers

    /// The routes that serve each page.
    ///
    /// - Parameter pages: The pages.
    /// - Returns: The reply of each page, keyed by its URL.
    private static func routes(serving pages: [WebRunPage]) -> [String: WebStubReply] {
        Dictionary(uniqueKeysWithValues: pages.map { ($0.url, $0.reply) })
    }

    /// The JavaScript string literal of a text.
    ///
    /// - Parameter text: The text.
    /// - Returns: The literal, with its quotes.
    private static func literal(_ text: String) -> String {
        ToolAPIRenderer.jsStringLiteral(text)
    }

    // MARK: - Search then fetch

    @Test("the search-then-fetch snippet of web.md returns three pages with titles and content heads")
    func goalSnippetReturnsThreePages() async throws {
        let pages = WebRunPage.pages(count: Self.searchHitCount)
        var routes = Self.routes(serving: pages)
        routes[try WebRun.searchURL()] = WebRun.searchReply(hitting: pages.map(\.url))
        let run = try WebRun(routes: routes)

        let output = try await run.runSnippet(
            """
            const hits = await tools.web.search({ query: \(Self.literal(WebRun.query)) });
            const pages = await Promise.all(
              hits.results.slice(0, \(Self.fetchedPageCount)).map(r => tools.web.fetch({ url: r.url, maxCharacters: \(Self.maxCharacters) })));
            return pages.map(p => ({ url: p.url, title: p.title, head: p.content.slice(0, \(Self.headLength)) }));
            """)

        #expect(!output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let heads = try RunOutput.decoded([WebPageHead].self, from: output)
        let fetched = pages.prefix(Self.fetchedPageCount)
        let expected = fetched.map { page in
            WebPageHead(url: page.url, title: page.title, head: String(page.markdown.prefix(Self.headLength)))
        }
        #expect(heads == expected)
        #expect(Set(run.stub.requestedURLs).isSuperset(of: fetched.map(\.url)))
        #expect(!run.stub.requestedURLs.contains(pages[Self.fetchedPageCount].url))
    }

    // MARK: - Parallel fetches

    @Test("Promise.all over three fetches returns three results")
    func promiseAllOverThreeFetchesReturnsThreeResults() async throws {
        let pages = WebRunPage.pages(count: Self.fetchedPageCount)
        let run = try WebRun(routes: Self.routes(serving: pages))
        let calls = pages.map { "tools.web.fetch({ url: \(Self.literal($0.url)) })" }

        let output = try await run.runSnippet(
            """
            const results = await Promise.all([\(calls.joined(separator: ", "))]);
            return results.map(r => r.correction || r.title);
            """)

        let titles = try RunOutput.decoded([String].self, from: output)
        #expect(titles == pages.map(\.title))
    }

    // MARK: - Corrections inside JavaScript

    /// The value that the correction snippet returns: the correction of each
    /// call.
    private struct CorrectionValue: Decodable {
        /// The correction of the fetch that the guard refused.
        let refused: String

        /// The correction of the fetch with a bad `url` argument.
        let invalid: String
    }

    @Test("a guard refusal and a bad argument reach the snippet as values with a correction")
    func refusalAndBadArgumentComeBackAsValues() async throws {
        let run = try WebRun(routes: [:])

        let output = try await run.runSnippet(
            """
            try {
              const refused = await tools.web.fetch({ url: \(Self.literal(Self.blockedURL)) });
              const invalid = await tools.web.fetch({ url: \(Self.literal(Self.badSchemeURL)) });
              return { refused: refused.correction, invalid: invalid.correction };
            } catch (error) {
              return \(Self.literal(Self.thrownMarker)) + ": " + error;
            }
            """)

        #expect(!output.contains(Self.thrownMarker), "output was: \(output)")
        let value = try RunOutput.decoded(CorrectionValue.self, from: output)
        #expect(value.refused == Self.blockedCorrection)
        #expect(value.invalid == Self.badSchemeCorrection)
        #expect(run.stub.requests.isEmpty)
    }

    // MARK: - The key stays in Swift

    /// The value that the keyed search snippet returns.
    private struct KeyedSearchValue: Decodable {
        /// The name of the provider that gave the hits.
        let provider: String

        /// The URL of each hit.
        let urls: [String]
    }

    @Test("a keyed provider answers the search, and its key is in no return value and no console output")
    func keyedSearchKeepsTheKeyOutOfEachOutput() async throws {
        let page = WebRunPage(index: 1)
        let searchURL = try WebRun.searchURL()
        var routes = Self.routes(serving: [page])
        routes[searchURL] = WebRun.searchReply(hitting: [page.url])
        let run = try WebRun(routes: routes)

        let searched = try await run.runSnippet(
            """
            const hits = await tools.web.search({ query: \(Self.literal(WebRun.query)) });
            return { provider: hits.provider, urls: hits.results.map(r => r.url) };
            """)
        let logged = try await run.runSnippet(
            """
            const hits = await tools.web.search({ query: \(Self.literal(WebRun.query)) });
            console.log(JSON.stringify(hits));
            const page = await tools.web.fetch({ url: hits.results[0].url });
            console.log(JSON.stringify(page));
            const refused = await tools.web.fetch({ url: \(Self.literal(Self.blockedURL)) });
            console.log(JSON.stringify(refused));
            console.log(docs("web.search"));
            console.log(docs("web.fetch"));
            return JSON.stringify({ hits, page, refused });
            """)

        let value = try RunOutput.decoded(KeyedSearchValue.self, from: searched)
        #expect(value.provider == WebSearchProvider.braveAPI(.literal(WebRun.testKey)).name)
        #expect(value.urls == [page.url])
        #expect(logged.contains(page.title), "output was: \(logged)")
        #expect(!logged.contains(WebRun.testKey))
        let searchHeaders = run.stub.requests.filter { $0.url.absoluteString == searchURL }.map(\.headers)
        #expect(!searchHeaders.isEmpty)
        #expect(searchHeaders.allSatisfy { $0[KeyedProviderCase.braveAPI.keyHeader] == WebRun.testKey })
    }
}
