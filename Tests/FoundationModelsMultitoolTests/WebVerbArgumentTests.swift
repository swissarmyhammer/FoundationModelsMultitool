import Foundation
@testable import FoundationModelsMultitool
import FoundationModels
import FoundationModelsRouter
import Testing

/// Tests for the arguments and the results of the two web verbs, `search`
/// and `fetch` (web.md § "The surface" and § "Corrections, not throws").
///
/// Each bad argument gives the documented correction, and the verb does not
/// throw. Each good bound value goes through to the network layer, which a
/// `WebStub` answers. Thus no test uses the network.
@Suite("WebVerbArgument")
struct WebVerbArgumentTests {
    // MARK: Search bounds

    /// The largest number of characters in a query.
    private static let maximumQueryLength = 500

    /// The largest `count`.
    private static let maximumCount = 20

    /// The `count` of a search that omits it.
    private static let defaultCount = 10

    /// The number of results in the reply that proves the default count. It
    /// is more than ``defaultCount``.
    private static let manyResults = 12

    /// The site of the accepted site test.
    private static let hostSite = "developer.apple.com"

    /// The correction for a bad `query`.
    private static let queryCorrection =
        "The `query` parameter must have 1 to 500 characters after the white space at each end is removed."

    /// The correction for a bad `count`.
    private static let countCorrection = "The `count` parameter must be a result count between 1 and 20."

    /// The correction for a bad `freshness`.
    private static let freshnessCorrection = "The `freshness` parameter must be one of: day, month, week, year."

    /// The correction for a bad `site`, before the value.
    private static let siteCorrectionLead =
        "The `site` parameter must be one host name, for example developer.apple.com: "

    // MARK: Fetch bounds

    /// The smallest `maxCharacters`.
    private static let minimumMaxCharacters = 500

    /// The largest `maxCharacters`.
    private static let maximumMaxCharacters = 200_000

    /// The largest `timeout`, in seconds.
    private static let maximumTimeout = 120

    /// The correction for a bad `url`, before the value.
    private static let urlCorrectionLead = "The `url` parameter must be an absolute http or https URL: "

    /// The correction for a bad `format`.
    private static let formatCorrection = "The `format` parameter must be one of: markdown, raw, text."

    /// The correction for a bad `offset`.
    private static let offsetCorrection = "The `offset` parameter must be a character offset of 0 or more."

    /// The correction for a bad `maxCharacters`.
    private static let maxCharactersCorrection =
        "The `maxCharacters` parameter must be a character count between 500 and 200000."

    /// The correction for a bad `timeout`.
    private static let timeoutCorrection = "The `timeout` parameter must be a number of seconds between 1 and 120."

    /// The HTTP status of a rate limit.
    private static let tooManyRequestsStatus = 429

    /// A small byte limit for the truncation test.
    private static let smallByteLimit = 64

    /// The text of the plain page of the fetch tests.
    private static let pageText = "The page text."

    /// The body of the HTML page of the fetch tests. The markdown form and
    /// the raw form of it are different.
    private static let htmlPage = "<html><head><title>Page Title</title></head><body><p>Hello.</p></body></html>"

    /// A fixture whose SearXNG instance gives results for one query.
    ///
    /// - Parameters:
    ///   - query: The query that the verb must send. The default is the
    ///     query of the fixture with no other field.
    ///   - count: The number of results in the reply.
    /// - Returns: The fixture.
    private static func searchFixture(
        for query: SearchQuery = SearchQuery(text: WebVerbFixture.query), resultCount count: Int = manyResults
    ) throws -> WebVerbFixture {
        try WebVerbFixture(routes: [
            WebVerbFixture.searxngSearchURL(for: query): WebVerbFixture.searxngReply(resultCount: count)
        ])
    }

    /// A fixture whose page URL gives a plain text page.
    ///
    /// - Parameter url: The URL text of the page, as the session sends it.
    /// - Returns: The fixture.
    private static func pageFixture(url: String = WebVerbFixture.pageURL) throws -> WebVerbFixture {
        try WebVerbFixture(routes: [url: WebVerbFixture.textReply(contentType: "text/plain", body: pageText)])
    }

    // MARK: Search

    @Test(
        "a bad query gives the query correction",
        arguments: ["", "   ", String(repeating: "q", count: maximumQueryLength + 1)])
    func badQueryIsCorrected(query: String) async throws {
        let result = try await WebVerbFixture().search(query)
        #expect(result.correction == Self.queryCorrection)
        #expect(result.results.isEmpty)
    }

    @Test("a query of 500 characters goes to the provider")
    func longestQueryIsAccepted() async throws {
        let query = String(repeating: "q", count: Self.maximumQueryLength)
        let result = try await Self.searchFixture(for: SearchQuery(text: query), resultCount: 1).search(query)
        #expect(result.correction == nil)
        #expect(result.results.count == 1)
    }

    @Test("the query is trimmed before the provider gets it")
    func queryIsTrimmed() async throws {
        let result = try await Self.searchFixture().search("  \(WebVerbFixture.query)\n")
        #expect(result.correction == nil)
    }

    @Test("a count out of 1 to 20 gives the count correction", arguments: [0, maximumCount + 1])
    func badCountIsCorrected(count: Int) async throws {
        let result = try await WebVerbFixture().search(count: count)
        #expect(result.correction == Self.countCorrection)
    }

    @Test("a count of 1 or 20 limits the results", arguments: [1, maximumCount])
    func boundCountIsAccepted(count: Int) async throws {
        let query = SearchQuery(text: WebVerbFixture.query, count: count)
        let fixture = try Self.searchFixture(for: query, resultCount: Self.maximumCount + 1)
        let result = try await fixture.search(count: count)
        #expect(result.correction == nil)
        #expect(result.results.count == count)
    }

    @Test("a search with no count gives at most 10 results")
    func defaultCountIsTen() async throws {
        let result = try await Self.searchFixture().search()
        #expect(result.results.count == Self.defaultCount)
    }

    @Test(
        "each freshness value is accepted in any case",
        arguments: [
            ("day", SearchFreshness.day), ("week", .week), ("month", .month), ("year", .year), ("DAY", .day),
            ("Week", .week)
        ])
    func freshnessIsAccepted(name: String, freshness: SearchFreshness) async throws {
        let query = SearchQuery(text: WebVerbFixture.query, freshness: freshness)
        let result = try await Self.searchFixture(for: query, resultCount: 1).search(freshness: name)
        #expect(result.correction == nil)
        #expect(result.results.count == 1)
    }

    @Test("an upper-case freshness gives the same result as the lower-case name")
    func upperCaseFreshnessMatchesLowerCase() async throws {
        let freshness = SearchFreshness.day
        let query = SearchQuery(text: WebVerbFixture.query, freshness: freshness)
        let fixture = try Self.searchFixture(for: query, resultCount: 1)
        let lowerCase = try await fixture.search(freshness: freshness.rawValue)
        let upperCase = try await fixture.search(freshness: freshness.rawValue.uppercased())
        #expect(lowerCase.results.count == 1)
        #expect(upperCase.correction == lowerCase.correction)
        #expect(upperCase.provider == lowerCase.provider)
        #expect(upperCase.results == lowerCase.results)
        #expect(upperCase.notes == lowerCase.notes)
    }

    @Test("an unknown freshness gives the freshness correction")
    func badFreshnessIsCorrected() async throws {
        let result = try await WebVerbFixture().search(freshness: "hour")
        #expect(result.correction == Self.freshnessCorrection)
    }

    @Test(
        "a site that is not one host name gives the site correction",
        arguments: ["https://apple.com/x", "apple.com/x", "apple com", "", "apple.com:443", "apple_com"])
    func badSiteIsCorrected(site: String) async throws {
        let result = try await WebVerbFixture().search(site: site)
        #expect(result.correction == Self.siteCorrectionLead + site)
    }

    @Test("a host name site goes to the provider as a site term")
    func hostNameSiteIsAccepted() async throws {
        let query = SearchQuery(text: WebVerbFixture.query, site: Self.hostSite)
        let result = try await Self.searchFixture(for: query, resultCount: 1).search(site: Self.hostSite)
        #expect(result.correction == nil)
        #expect(result.results.count == 1)
    }

    @Test("a stubbed search gives the provider, the hits, and no notes")
    func searchResultShape() async throws {
        let body = try KeyedProviderCase.searxng.recordedResponse()
        let reply = WebStubReply.respond(status: WebStub.okStatus, headers: WebVerbFixture.jsonHeaders, body: body)
        let fixture = try WebVerbFixture(routes: [WebVerbFixture.searxngSearchURL(): reply])
        let result = try await fixture.search()
        #expect(result.provider == "searxng")
        #expect(result.results == (try KeyedProviderCase.searxng.parse(body)))
        #expect(result.notes == nil)
        #expect(result.correction == nil)
    }

    @Test("a provider that the chain skips adds a note")
    func skippedProviderAddsANote() async throws {
        let fixture = try WebVerbFixture(
            routes: [WebVerbFixture.searxngSearchURL(): WebVerbFixture.searxngReply(resultCount: 1)],
            providers: [.braveAPI(.environment("WEB_VERB_UNSET_KEY")), WebVerbFixture.searxngProvider()])
        let result = try await fixture.search()
        #expect(result.notes == ["braveAPI: skipped, WEB_VERB_UNSET_KEY is not set."])
    }

    @Test("a failed search gives a correction and no results")
    func failedSearchIsCorrected() async throws {
        let blocked = WebVerbFixture.textReply(status: Self.tooManyRequestsStatus, contentType: "text/plain", body: "")
        let fixture = try WebVerbFixture(routes: [WebVerbFixture.searxngSearchURL(): blocked])
        let result = try await fixture.search()
        #expect(result.correction == "No search provider gave results. searxng: blocked (HTTP 429).")
        #expect(result.results.isEmpty)
        #expect(result.provider.isEmpty)
    }
}

/// The fetch tests and the tests of both verbs. They are in an extension,
/// thus each part of the suite stays short.
extension WebVerbArgumentTests {
    // MARK: Fetch

    @Test(
        "a URL that is not absolute http or https gives the url correction",
        arguments: ["ftp://x", "not a url", "/relative/page", "https://", "mailto:someone@site.example"])
    func badURLIsCorrected(url: String) async throws {
        let result = try await WebVerbFixture().fetch(url)
        #expect(result.correction == Self.urlCorrectionLead + url)
        #expect(result.content.isEmpty)
    }

    @Test("an upper-case scheme is an http URL")
    func upperCaseSchemeIsAccepted() async throws {
        let url = "HTTPS://site.example/page"
        let result = try await Self.pageFixture(url: url).fetch(url)
        #expect(result.correction == nil)
        #expect(result.content == Self.pageText)
    }

    @Test("each format value is accepted in any case", arguments: ["markdown", "text", "raw", "RAW"])
    func formatIsAccepted(format: String) async throws {
        let result = try await Self.pageFixture().fetch(format: format)
        #expect(result.correction == nil)
    }

    @Test("an upper-case format gives the same content as the lower-case name")
    func upperCaseFormatMatchesLowerCase() async throws {
        let fixture = try WebVerbFixture(routes: [
            WebVerbFixture.pageURL: WebVerbFixture.textReply(contentType: "text/html", body: Self.htmlPage)
        ])
        let format = WebPageFormat.raw
        let lowerCase = try await fixture.fetch(format: format.rawValue)
        let upperCase = try await fixture.fetch(format: format.rawValue.uppercased())
        #expect(upperCase.correction == nil)
        #expect(upperCase.content == lowerCase.content)
        #expect(upperCase.content == Self.htmlPage)
    }

    @Test("an unknown format gives the format correction")
    func badFormatIsCorrected() async throws {
        let result = try await WebVerbFixture().fetch(format: "pdf")
        #expect(result.correction == Self.formatCorrection)
    }

    @Test("a negative offset gives the offset correction")
    func negativeOffsetIsCorrected() async throws {
        let result = try await WebVerbFixture().fetch(offset: -1)
        #expect(result.correction == Self.offsetCorrection)
    }

    @Test("an offset of 0 is accepted")
    func zeroOffsetIsAccepted() async throws {
        let result = try await Self.pageFixture().fetch(offset: 0)
        #expect(result.correction == nil)
    }

    @Test(
        "a maxCharacters out of 500 to 200000 gives the maxCharacters correction",
        arguments: [minimumMaxCharacters - 1, maximumMaxCharacters + 1])
    func badMaxCharactersIsCorrected(maxCharacters: Int) async throws {
        let result = try await WebVerbFixture().fetch(maxCharacters: maxCharacters)
        #expect(result.correction == Self.maxCharactersCorrection)
    }

    @Test("a maxCharacters of 500 or 200000 is accepted", arguments: [minimumMaxCharacters, maximumMaxCharacters])
    func boundMaxCharactersIsAccepted(maxCharacters: Int) async throws {
        let result = try await Self.pageFixture().fetch(maxCharacters: maxCharacters)
        #expect(result.correction == nil)
    }

    @Test("a timeout out of 1 to 120 gives the timeout correction", arguments: [0, maximumTimeout + 1])
    func badTimeoutIsCorrected(timeout: Int) async throws {
        let result = try await WebVerbFixture().fetch(timeout: timeout)
        #expect(result.correction == Self.timeoutCorrection)
    }

    @Test("a timeout of 1 or 120 is accepted", arguments: [1, maximumTimeout])
    func boundTimeoutIsAccepted(timeout: Int) async throws {
        let result = try await Self.pageFixture().fetch(timeout: timeout)
        #expect(result.correction == nil)
    }

    @Test("a stubbed HTML page gives the URL, the status, the type, the title, and the content")
    func fetchResultShape() async throws {
        let fixture = try WebVerbFixture(routes: [
            WebVerbFixture.pageURL: WebVerbFixture.textReply(
                contentType: "text/html; charset=utf-8", body: Self.htmlPage)
        ])
        let result = try await fixture.fetch()
        #expect(result.url == WebVerbFixture.pageURL)
        #expect(result.status == WebStub.okStatus)
        #expect(result.contentType == "text/html")
        #expect(result.title == "Page Title")
        #expect(result.content == "Hello.\n")
        #expect(result.totalCharacters == result.content.count)
        #expect(result.nextOffset == nil)
        #expect(result.notes == nil)
        #expect(result.correction == nil)
    }

    @Test("a non-2xx page is a normal result with its status and its content")
    func notFoundPageIsAResult() async throws {
        let fixture = try WebVerbFixture(routes: [
            WebVerbFixture.pageURL: WebVerbFixture.textReply(
                status: WebStub.notFoundStatus, contentType: "text/plain", body: Self.pageText)
        ])
        let result = try await fixture.fetch()
        #expect(result.status == WebStub.notFoundStatus)
        #expect(result.content == Self.pageText)
        #expect(result.correction == nil)
    }

    @Test("a failed fetch gives a correction and no content")
    func failedFetchIsCorrected() async throws {
        let fixture = try WebVerbFixture(routes: [WebVerbFixture.pageURL: .fail(.cannotConnectToHost)])
        let result = try await fixture.fetch()
        let correction = try #require(result.correction)
        #expect(correction.hasPrefix("The request to \(WebVerbFixture.pageURL) failed: "))
        #expect(result.content.isEmpty)
        #expect(result.url == WebVerbFixture.pageURL)
    }

    @Test("a body larger than the byte limit gives the truncation note")
    func truncatedBodyAddsANote() async throws {
        let body = String(repeating: "x", count: Self.smallByteLimit * 2)
        let fixture = try WebVerbFixture(
            routes: [WebVerbFixture.pageURL: WebVerbFixture.textReply(contentType: "text/plain", body: body)],
            policy: WebFetchPolicy(maxBytes: Self.smallByteLimit))
        let result = try await fixture.fetch()
        #expect(result.notes == ["The download stopped at 64 bytes. The page is not complete."])
        #expect(result.content.count == Self.smallByteLimit)
        #expect(result.correction == nil)
    }

    // MARK: The verbs

    @Test("neither verb conforms to BackgroundTool")
    func neitherVerbIsABackgroundTool() throws {
        let context = try WebVerbFixture().context
        #expect(!((Search(context: context) as Any) is any BackgroundTool))
        #expect(!((Fetch(context: context) as Any) is any BackgroundTool))
    }

    @Test("each verb has its name, and its description names search then fetch and Promise.all")
    func verbNamesAndDescriptions() throws {
        let context = try WebVerbFixture().context
        let search = Search(context: context)
        let fetch = Fetch(context: context)
        #expect(search.name == "search")
        #expect(fetch.name == "fetch")
        for description in [search.description, fetch.description] {
            #expect(description.contains("tools.web.search"))
            #expect(description.contains("tools.web.fetch"))
            #expect(description.contains("Promise.all"))
        }
    }
}
