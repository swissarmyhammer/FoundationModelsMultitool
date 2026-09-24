import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `WebPageReader`: the conversion of each format, the windows, the
/// page cache, the eviction of the least recently used page, the non-2xx
/// page, the `truncated` flag, and `networkLoadCount`.
///
/// A `WebStub` answers each request, thus no test uses the network.
@Suite("WebPageReader")
struct WebPageReaderTests {
    /// The URL of the page that most tests read.
    private static let pageURL = "https://site.example/page"

    /// The `http` URL that redirects to ``secureURL``.
    private static let plainURL = "http://a.test/"

    /// The `https` URL that ``plainURL`` redirects to.
    private static let secureURL = "https://a.test/"

    /// The `Content-Type` header name.
    private static let contentType = "Content-Type"

    /// The media type of an HTML page.
    private static let htmlType = "text/html"

    /// The HTML of the page that most tests read.
    private static let pageHTML = """
        <html><head><title>Page Title</title></head>
        <body><h1>Heading</h1><p>Alpha <em>beta</em> gamma.</p><p>Delta epsilon.</p></body></html>
        """

    /// The markdown of ``pageHTML``.
    private static let pageMarkdown = "# Heading\n\nAlpha *beta* gamma.\n\nDelta epsilon.\n"

    /// The plain text of ``pageHTML``.
    private static let pageText = "Heading\n\nAlpha beta gamma.\n\nDelta epsilon.\n"

    /// A window size that makes more than one window of ``pageMarkdown``.
    private static let smallWindow = 7

    /// A window size that holds each test page whole.
    private static let wholeWindow = 200_000

    /// The number of pages that the cache keeps.
    private static let cacheCapacity = 16

    /// A distance in characters past the end of ``pageMarkdown``.
    private static let pastEndDistance = 5

    /// The number of loads when two reads each go to the network.
    private static let twoLoads = 2

    /// The number of URLs that redirect to ``secureURL`` in the shared-entry
    /// test.
    private static let redirectingURLCount = 2

    /// A byte limit that is smaller than ``pageHTML``.
    private static let smallByteLimit = 16

    /// A `200` HTML reply with `html` as its body.
    ///
    /// - Parameter html: The body.
    /// - Returns: The reply.
    private static func htmlReply(_ html: String = pageHTML) -> WebStubReply {
        .respond(status: WebStub.okStatus, headers: [contentType: htmlType], body: Data(html.utf8))
    }

    /// Reads one window of `url` with the ample time limit of the stub.
    ///
    /// - Parameters:
    ///   - reader: The reader.
    ///   - url: The URL text.
    ///   - format: The format of the content.
    ///   - offset: The character offset of the window.
    ///   - maxCharacters: The size of the window.
    /// - Returns: The result of the read.
    private static func read(
        _ reader: WebPageReader,
        _ url: String,
        format: WebPageFormat = .markdown,
        offset: Int = 0,
        maxCharacters: Int = wholeWindow
    ) async throws -> Result<PageWindow, WebFetchFailure> {
        try await reader.read(
            url: #require(URL(string: url)), format: format, offset: offset, maxCharacters: maxCharacters,
            timeout: WebStub.ampleTimeout
        )
    }

    /// The URL text of the page with number `index`, for the eviction test.
    ///
    /// - Parameter index: The number of the page.
    /// - Returns: The URL text.
    private static func numberedURL(_ index: Int) -> String {
        "https://site.example/page-\(index)"
    }

    // MARK: - Windows

    @Test("the windows from offset 0 through each nextOffset join to the full text")
    func windowsJoinToFullText() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        var pieces: [String] = []
        var offset: Int? = 0
        while let start = offset {
            let window = try await Self.read(reader, Self.pageURL, offset: start, maxCharacters: Self.smallWindow).get()
            #expect(window.totalCharacters == Self.pageMarkdown.count)
            #expect(window.content.count <= Self.smallWindow)
            pieces.append(window.content)
            offset = window.nextOffset
        }
        #expect(pieces.joined() == Self.pageMarkdown)
        #expect(pieces.count == (Self.pageMarkdown.count + Self.smallWindow - 1) / Self.smallWindow)
    }

    @Test("a window gives the final URL, the status, the content type, and the title")
    func windowGivesResponseFields() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL).get()
        #expect(window.url.absoluteString == Self.pageURL)
        #expect(window.status == WebStub.okStatus)
        #expect(window.contentType == Self.htmlType)
        #expect(window.title == "Page Title")
        #expect(window.content == Self.pageMarkdown)
        #expect(window.nextOffset == nil)
        #expect(!window.truncated)
    }

    @Test(
        "an offset at the end or past the end gives empty content and no next offset",
        arguments: [0, pastEndDistance]
    )
    func offsetPastEndIsEmpty(extra: Int) async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        let window = try await Self.read(reader, Self.pageURL, offset: Self.pageMarkdown.count + extra).get()
        #expect(window.content.isEmpty)
        #expect(window.nextOffset == nil)
        #expect(window.totalCharacters == Self.pageMarkdown.count)
    }

    // MARK: - Formats

    @Test("the text format gives the page with no markdown marks")
    func textFormatHasNoMarks() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL, format: .text).get()
        #expect(window.content == Self.pageText)
        #expect(window.title == "Page Title")
    }

    @Test("the raw format of an HTML page gives the HTML with no change")
    func rawFormatGivesHTML() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL, format: .raw).get()
        #expect(window.content == Self.pageHTML)
        #expect(window.totalCharacters == Self.pageHTML.count)
    }

    @Test("an application/xhtml+xml page is converted as HTML")
    func xhtmlIsConverted() async throws {
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: [Self.contentType: "application/xhtml+xml"],
            body: Data(Self.pageHTML.utf8)
        )
        let stub = WebStub(routes: [Self.pageURL: reply])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL).get()
        #expect(window.content == Self.pageMarkdown)
    }

    @Test("a text type that is not HTML is used as is in each format", arguments: [WebPageFormat.markdown, .text, .raw])
    func plainTextIsUsedAsIs(format: WebPageFormat) async throws {
        let json = #"{"name": "<b>value</b>"}"#
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: [Self.contentType: "application/json"], body: Data(json.utf8)
        )
        let stub = WebStub(routes: [Self.pageURL: reply])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL, format: format).get()
        #expect(window.content == json)
        #expect(window.title == nil)
    }

    @Test("a non-2xx page gives its status and its converted body")
    func notFoundPageGivesBody() async throws {
        let html = "<html><body><p>No such page.</p></body></html>"
        let reply = WebStubReply.respond(
            status: WebStub.notFoundStatus, headers: [Self.contentType: Self.htmlType], body: Data(html.utf8)
        )
        let stub = WebStub(routes: [Self.pageURL: reply])
        let window = try await Self.read(WebPageReader(fetcher: stub.makeFetcher()), Self.pageURL).get()
        #expect(window.status == WebStub.notFoundStatus)
        #expect(window.content == "No such page.\n")
    }

    @Test("a body that stops at the byte limit sets truncated on the window")
    func truncatedBodySetsTruncated() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let fetcher = stub.makeFetcher(policy: WebFetchPolicy(maxBytes: Self.smallByteLimit))
        let window = try await Self.read(WebPageReader(fetcher: fetcher), Self.pageURL, format: .raw).get()
        #expect(window.truncated)
        #expect(window.content == String(Self.pageHTML.prefix(Self.smallByteLimit)))
    }

    // MARK: - Failures

    @Test("a type that is not text gives the content-type failure, and the failure is not cached")
    func notTextFailsAndIsNotCached() async throws {
        let reply = WebStubReply.respond(
            status: WebStub.okStatus, headers: [Self.contentType: "application/pdf"], body: Data("%PDF-1.7".utf8)
        )
        let stub = WebStub(routes: [Self.pageURL: reply])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        let failure = WebFetchFailure.notText(contentType: "application/pdf")
        let first = try await Self.read(reader, Self.pageURL)
        #expect(throws: failure) { try first.get() }
        let second = try await Self.read(reader, Self.pageURL)
        #expect(throws: failure) { try second.get() }
        #expect(await reader.networkLoadCount == Self.twoLoads)
    }

    @Test("the unconvertible failure names the URL and the reason")
    func unconvertibleMessage() {
        let failure = WebFetchFailure.unconvertible(url: Self.pageURL, reason: "the parser stopped")
        #expect(failure.correctiveMessage == "The page at \(Self.pageURL) could not be converted: the parser stopped")
    }

    // MARK: - Cache

    @Test("a second window of the same page makes no new request")
    func secondWindowIsCacheHit() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        _ = try await Self.read(reader, Self.pageURL, maxCharacters: Self.smallWindow).get()
        let second = try await Self.read(
            reader, Self.pageURL, offset: Self.smallWindow, maxCharacters: Self.smallWindow
        ).get()
        #expect(second.content == String(Self.pageMarkdown.dropFirst(Self.smallWindow).prefix(Self.smallWindow)))
        #expect(stub.requestedURLs == [Self.pageURL])
        #expect(await reader.networkLoadCount == 1)
    }

    @Test("a second window of a URL that redirects makes no new request")
    func redirectedPageIsCacheHit() async throws {
        let stub = try WebStub(routes: [
            Self.plainURL: .redirect(location: #require(URL(string: Self.secureURL))),
            Self.secureURL: Self.htmlReply()
        ])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        let first = try await Self.read(reader, Self.plainURL, maxCharacters: Self.smallWindow).get()
        #expect(first.url.absoluteString == Self.secureURL)
        _ = try await Self.read(reader, Self.plainURL, offset: Self.smallWindow).get()
        _ = try await Self.read(reader, Self.secureURL).get()
        #expect(stub.requestedURLs == [Self.plainURL, Self.secureURL])
        #expect(await reader.networkLoadCount == 1)
    }

    @Test("two URLs that redirect to one page share one cache entry, and each URL still finds it")
    func sharedFinalURLIsOneEntry() async throws {
        let secure = try #require(URL(string: Self.secureURL))
        let otherPlainURL = "http://b.test/"
        let fillerCount = Self.cacheCapacity - 1
        var routes: [String: WebStubReply] = [
            Self.plainURL: .redirect(location: secure),
            otherPlainURL: .redirect(location: secure),
            Self.secureURL: Self.htmlReply()
        ]
        for index in 0..<fillerCount {
            routes[Self.numberedURL(index)] = Self.htmlReply()
        }
        let stub = WebStub(routes: routes)
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        _ = try await Self.read(reader, otherPlainURL).get()
        _ = try await Self.read(reader, Self.plainURL).get()
        for index in 0..<fillerCount {
            _ = try await Self.read(reader, Self.numberedURL(index)).get()
        }
        let loadsBefore = await reader.networkLoadCount
        _ = try await Self.read(reader, otherPlainURL).get()
        _ = try await Self.read(reader, Self.plainURL).get()
        #expect(loadsBefore == fillerCount + Self.redirectingURLCount)
        #expect(await reader.networkLoadCount == loadsBefore)
    }

    @Test("each format of a page is its own cache entry")
    func formatIsPartOfKey() async throws {
        let stub = WebStub(routes: [Self.pageURL: Self.htmlReply()])
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        let markdown = try await Self.read(reader, Self.pageURL, format: .markdown).get()
        let raw = try await Self.read(reader, Self.pageURL, format: .raw).get()
        #expect(markdown.content == Self.pageMarkdown)
        #expect(raw.content == Self.pageHTML)
        #expect(await reader.networkLoadCount == Self.twoLoads)
    }

    @Test("the seventeenth distinct page removes the least recently used page")
    func seventeenthPageEvictsLeastRecentlyUsed() async throws {
        let pageCount = Self.cacheCapacity + 1
        let routes = Dictionary(uniqueKeysWithValues: (0..<pageCount).map { (Self.numberedURL($0), Self.htmlReply()) })
        let stub = WebStub(routes: routes)
        let reader = WebPageReader(fetcher: stub.makeFetcher())
        for index in 0..<Self.cacheCapacity {
            _ = try await Self.read(reader, Self.numberedURL(index)).get()
        }
        _ = try await Self.read(reader, Self.numberedURL(0)).get()
        _ = try await Self.read(reader, Self.numberedURL(Self.cacheCapacity)).get()
        #expect(await reader.networkLoadCount == pageCount)
        _ = try await Self.read(reader, Self.numberedURL(0)).get()
        #expect(await reader.networkLoadCount == pageCount)
        _ = try await Self.read(reader, Self.numberedURL(1)).get()
        #expect(await reader.networkLoadCount == pageCount + 1)
    }
}
