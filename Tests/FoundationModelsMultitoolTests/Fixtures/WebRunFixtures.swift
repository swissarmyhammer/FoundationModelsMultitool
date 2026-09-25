// `WebRunFixtures` — a web surface over a stub session, and the one way to
// run a `runCode` snippet over it.
//
// A suite that proves what the web verbs give to a snippet needs the same
// ground each time: a `WebStub` that answers each request, a registry built
// with `MultiTool.Builder().withWeb(...)` over the stub session, and a
// `MultiTool` over that registry. `WebRun` is that ground, built one time here
// rather than once for each test.
//
// The configuration holds one keyed provider, `braveAPI`, with the literal
// test key ``WebRun/testKey``. The guard of the capability uses
// `PublicHostResolver`. Thus no request and no DNS lookup goes to the network.
//
// `WebRun.runSnippet(_:)` examines each output for the test key. Thus each
// snippet that a suite runs through this fixture proves that the key is in
// no return value and in no console output.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// A web surface over a stub session, with one keyed search provider.
///
/// The fixture keeps the stub, thus the stub stays registered while the test
/// runs its snippets.
struct WebRun {
    /// The literal key of the `braveAPI` provider. It is a fake value.
    static let testKey = "test-secret-123"

    /// The query of the search of each snippet.
    static let query = "swift structured concurrency"

    /// The stub that answers each request of the surface.
    let stub: WebStub

    /// The `runCode` tool over the web surface.
    let multiTool: MultiTool

    /// Makes a web surface whose session sends each request to a stub.
    ///
    /// - Parameter routes: The reply for each URL, keyed by the absolute URL
    ///   text. A URL with no row gets a `404` response with no body.
    /// - Throws: When the registry does not build.
    init(routes: [String: WebStubReply]) throws {
        stub = WebStub(routes: routes)
        let configuration = WebConfiguration(providers: [.braveAPI(.literal(Self.testKey))])
        let registry = try MultiTool.Builder()
            .withWeb(
                configuration: configuration, sessionConfiguration: stub.sessionConfiguration,
                resolver: PublicHostResolver())
            .buildRegistry()
        multiTool = MultiTool(registry: registry)
    }

    /// Runs one `runCode` snippet over the web surface.
    ///
    /// The call goes through the shared `runSnippet(_:through:under:)` of
    /// `FilesRunFixtures`, with no session context, thus through the JSC
    /// interpreter, the `tools.*` bindings, and `ToolInvoker`: the same path
    /// as the snippet of a model. The rendered output holds the return value
    /// and the console output. The function records an issue when the output
    /// holds ``testKey``.
    ///
    /// - Parameter code: The snippet to run.
    /// - Returns: The rendered output, as the model reads it.
    /// - Throws: What `MultiTool.call(arguments:)` throws.
    func runSnippet(_ code: String) async throws -> String {
        let output = try await FoundationModelsMultitoolTests.runSnippet(code, through: multiTool, under: nil)
        #expect(!output.contains(Self.testKey), "the output holds the key: \(output)")
        return output
    }

    /// The URL of the `braveAPI` search request of ``query``, as the adapter
    /// makes it.
    ///
    /// - Returns: The absolute URL text. It holds no key: the key goes in a
    ///   header.
    /// - Throws: When the adapter cannot make the request.
    static func searchURL() throws -> String {
        let request = try KeyedProviderCase.braveAPI.adapter.request(for: SearchQuery(text: query), key: testKey)
        return try #require(request.url?.absoluteString)
    }

    /// A `braveAPI` reply that holds one hit for each URL, in order.
    ///
    /// - Parameter urls: The URL of each hit. Hit `n` has the title
    ///   `Result n`.
    /// - Returns: The reply, with status 200.
    static func searchReply(hitting urls: [String]) -> WebStubReply {
        let results = urls.enumerated().map { position, url in
            FixtureResult(title: "Result \(position + 1)", url: url, snippet: "Snippet \(position + 1)")
        }
        let body = KeyedProviderCase.braveAPI.responseBody(results)
        return WebVerbFixture.textReply(contentType: WebVerbFixture.jsonContentType, body: body)
    }
}

/// One HTML page that a stub serves, and the markdown that `fetch` makes of
/// it.
struct WebRunPage {
    /// The number of times the sentence of the page repeats in its paragraph.
    /// The paragraph is then longer than each head that a snippet takes.
    private static let sentenceRepeats = 60

    /// The URL of the page.
    let url: String

    /// The text of the `<title>` element.
    let title: String

    /// The text of the one `<h1>` element.
    let heading: String

    /// The text of the one `<p>` element.
    let paragraph: String

    /// Makes page `index` at `https://page.example/<index>`.
    ///
    /// - Parameter index: The number of the page.
    init(index: Int) {
        url = "https://page.example/\(index)"
        title = "Page \(index)"
        heading = "Heading \(index)"
        paragraph = Array(repeating: "Page \(index) has this text.", count: Self.sentenceRepeats)
            .joined(separator: " ")
    }

    /// The pages `1...count`.
    ///
    /// - Parameter count: The number of pages.
    /// - Returns: The pages, in order.
    static func pages(count: Int) -> [WebRunPage] {
        (1...count).map(WebRunPage.init(index:))
    }

    /// The markdown that `fetch` gives for the page: the heading, one empty
    /// line, and the paragraph.
    var markdown: String {
        "# \(heading)\n\n\(paragraph)"
    }

    /// The reply that serves the page as `text/html`.
    var reply: WebStubReply {
        let html = "<html><head><title>\(title)</title></head>"
            + "<body><h1>\(heading)</h1><p>\(paragraph)</p></body></html>"
        return WebVerbFixture.textReply(contentType: "text/html; charset=utf-8", body: html)
    }
}
