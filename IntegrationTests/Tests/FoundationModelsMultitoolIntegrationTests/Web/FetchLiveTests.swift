import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The live tests of the `fetch` verb, over real pages (web.md § "Testing",
/// Level 2, the `FetchLiveTests` row).
///
/// Each test fetches one well-known page. The pages and the facts are stable
/// for years: the title of `example.com`, the `https` redirect of
/// `github.com`, the length of a Wikipedia article, the media type of the
/// GitHub zen API, and the media type of a W3C test PDF. A test does not
/// retry.
@Suite(
    "Live: the fetch verb reads real pages",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct FetchLiveTests {
    /// The page whose title and content are `Example Domain`.
    private static let exampleURL = "https://example.com"

    /// The title and a text of the content of ``exampleURL``.
    private static let exampleTitle = "Example Domain"

    /// The `http` URL that GitHub redirects to `https`.
    private static let plainGitHubURL = "http://github.com"

    /// The start of the final URL of ``plainGitHubURL``.
    private static let secureGitHubPrefix = "https://github.com"

    /// A long page: its markdown is much longer than ``windowSize``.
    private static let longPageURL = "https://en.wikipedia.org/wiki/Swift_(programming_language)"

    /// The window size of the two windows of ``longPageURL``.
    private static let windowSize = 2000

    /// The number of downloads that two windows of one page make: the second
    /// window comes from the page cache.
    private static let singleDownload = 1

    /// The GitHub API path that gives one line of plain text.
    private static let zenURL = "https://api.github.com/zen"

    /// The media type of ``zenURL``.
    private static let plainTextType = "text/plain"

    /// A small PDF file of the W3C accessibility tests.
    private static let pdfURL = "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"

    /// The correction of the `fetch` verb for ``pdfURL``.
    private static let pdfCorrection =
        "The content type is not text: application/pdf. fetch reads text, HTML, JSON, and XML."

    @Test("example.com gives the title Example Domain, and the content holds Example Domain")
    func examplePageGivesItsTitle() async throws {
        let result = try await WebVerbCall.fetch(Self.exampleURL, context: LiveFetch.makeContext())

        try LiveFetch.requireNoCorrection(result)
        #expect(result.title == Self.exampleTitle)
        #expect(result.content.contains(Self.exampleTitle), "the content was: \(result.content)")
    }

    @Test("http://github.com redirects, and the final URL starts with https://github.com")
    func plainGitHubRedirectsToHTTPS() async throws {
        let result = try await WebVerbCall.fetch(Self.plainGitHubURL, context: LiveFetch.makeContext())

        try LiveFetch.requireNoCorrection(result)
        #expect(result.url.hasPrefix(Self.secureGitHubPrefix), "the final URL was: \(result.url)")
    }

    @Test("a second window of a long page gives the next text, from the cache and with no second download")
    func secondWindowComesFromTheCache() async throws {
        let context = LiveFetch.makeContext()
        let first = try await WebVerbCall.fetch(Self.longPageURL, maxCharacters: Self.windowSize, context: context)
        try LiveFetch.requireNoCorrection(first)
        let nextOffset = try #require(first.nextOffset, "the first window is the whole page")

        let second = try await WebVerbCall.fetch(
            Self.longPageURL, offset: nextOffset, maxCharacters: Self.windowSize, context: context)

        try LiveFetch.requireNoCorrection(second)
        #expect(!second.content.isEmpty)
        #expect(second.content != first.content)
        #expect(second.totalCharacters == first.totalCharacters)
        #expect(await context.reader.networkLoadCount == Self.singleDownload)
    }

    @Test("the GitHub zen API gives text/plain content that is not empty")
    func zenGivesPlainText() async throws {
        let result = try await WebVerbCall.fetch(Self.zenURL, context: LiveFetch.makeContext())

        try LiveFetch.requireNoCorrection(result)
        #expect(result.contentType == Self.plainTextType)
        #expect(!result.content.isEmpty)
    }

    @Test("a PDF gives the correction for a type that is not text")
    func pdfGivesTheBinaryCorrection() async throws {
        let result = try await WebVerbCall.fetch(Self.pdfURL, context: LiveFetch.makeContext())

        #expect(result.correction == Self.pdfCorrection)
    }
}
