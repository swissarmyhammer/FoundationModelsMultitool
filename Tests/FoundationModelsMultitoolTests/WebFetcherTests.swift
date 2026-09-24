import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `WebFetcher`: the byte limit, the status, the response fields,
/// the text decode, the timeout, the `User-Agent`, the cookies, and the
/// unguarded request for host configuration.
///
/// A `WebStub` answers each request, thus no test uses the network.
@Suite("WebFetcher")
struct WebFetcherTests {
    /// The URL of a page that each test loads.
    private static let pageURL = "https://site.example/page"

    /// The URL of a second page on the same host.
    private static let secondPageURL = "https://site.example/second"

    /// The URL of the SearXNG instance that a host runs on its own computer.
    private static let searxngURL = "http://127.0.0.1:8888/search"

    /// The `Content-Type` header name.
    private static let contentType = "Content-Type"

    /// The `User-Agent` header name.
    private static let userAgent = "User-Agent"

    /// A byte limit that is small, so a test body can go past it.
    private static let smallLimit = 16

    /// A body size that is larger than ``smallLimit``.
    private static let oversizeCount = 64

    /// The time limit of a request that must time out.
    private static let shortTimeout: Duration = .milliseconds(200)

    /// The default fetch time limit of the design, in whole seconds.
    private static let defaultTimeout: Duration = .seconds(30)

    /// A time limit that is part of a second.
    private static let halfSecond: Duration = .milliseconds(500)

    /// Loads ``pageURL`` from a stub that gives `reply` for it.
    ///
    /// - Parameters:
    ///   - reply: What the stub does with the request.
    ///   - policy: The policy of the fetcher.
    ///   - timeout: The time limit of the load.
    /// - Returns: The stub, and the result of the load.
    private static func loadPage(
        _ reply: WebStubReply,
        policy: WebFetchPolicy = WebFetchPolicy(),
        timeout: Duration = WebStub.ampleTimeout
    ) async throws -> (stub: WebStub, result: Result<FetchedBody, WebFetchFailure>) {
        let stub = WebStub(routes: [pageURL: reply])
        let result = try await stub.makeFetcher(policy: policy)
            .load(WebStub.request(to: pageURL), timeout: timeout)
        return (stub, result)
    }

    /// Loads ``pageURL`` with a `200` response of `body` and a `Content-Type`
    /// of `type`, and decodes the body as text.
    ///
    /// - Parameters:
    ///   - body: The body of the response.
    ///   - type: The `Content-Type` header, or `nil` for no header.
    /// - Returns: The result of `decodeText(_:)` on the body that the fetcher
    ///   read.
    private static func decodedPage(_ body: Data, type: String?) async throws
        -> Result<String, WebFetchFailure>
    {
        let headers = type.map { [contentType: $0] } ?? [:]
        let stub = WebStub(routes: [pageURL: .respond(status: WebStub.okStatus, headers: headers, body: body)])
        let fetcher = stub.makeFetcher()
        let fetched = try await fetcher.load(WebStub.request(to: pageURL), timeout: WebStub.ampleTimeout).get()
        return fetcher.decodeText(fetched)
    }

    // MARK: - Body

    @Test("a body larger than maxBytes stops at the limit and is truncated")
    func bodyPastLimitIsTruncated() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: Self.oversizeCount)
        let (_, result) = try await Self.loadPage(
            .respond(status: WebStub.okStatus, headers: [:], body: body),
            policy: WebFetchPolicy(maxBytes: Self.smallLimit)
        )
        let fetched = try result.get()
        #expect(fetched.bytes == body.prefix(Self.smallLimit))
        #expect(fetched.truncated)
    }

    @Test("a body of exactly maxBytes is complete and not truncated")
    func bodyAtLimitIsComplete() async throws {
        let body = Data(repeating: UInt8(ascii: "b"), count: Self.smallLimit)
        let (_, result) = try await Self.loadPage(
            .respond(status: WebStub.okStatus, headers: [:], body: body),
            policy: WebFetchPolicy(maxBytes: Self.smallLimit)
        )
        let fetched = try result.get()
        #expect(fetched.bytes == body)
        #expect(!fetched.truncated)
    }

    @Test("a non-2xx status is a normal result with its body")
    func notFoundIsNormalResult() async throws {
        let body = Data("no such page".utf8)
        let (_, result) = try await Self.loadPage(
            .respond(status: WebStub.notFoundStatus, headers: [:], body: body)
        )
        let fetched = try result.get()
        #expect(fetched.status == WebStub.notFoundStatus)
        #expect(fetched.bytes == body)
    }

    @Test("the final URL, the media type, and the charset come from the last response")
    func responseFieldsAreRead() async throws {
        let stub = try WebStub(routes: [
            Self.pageURL: .redirect(location: #require(URL(string: Self.secondPageURL))),
            Self.secondPageURL: .respond(
                status: WebStub.okStatus, headers: [Self.contentType: #"Text/HTML; Charset="UTF-8""#], body: Data()
            ),
        ])
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.pageURL), timeout: WebStub.ampleTimeout)
        let fetched = try result.get()
        #expect(fetched.url.absoluteString == Self.secondPageURL)
        #expect(fetched.status == WebStub.okStatus)
        #expect(fetched.contentType == "text/html")
        #expect(fetched.charset == "utf-8")
    }

    // MARK: - Text decode

    @Test("a PDF content type gives the content-type failure")
    func pdfIsNotText() async throws {
        let decoded = try await Self.decodedPage(Data("%PDF-1.7".utf8), type: "application/pdf")
        let failure = WebFetchFailure.notText(contentType: "application/pdf")
        #expect(throws: failure) { try decoded.get() }
        #expect(
            failure.correctiveMessage
                == "The content type is not text: application/pdf. fetch reads text, HTML, JSON, and XML."
        )
    }

    @Test("a response with no content type gives the content-type failure")
    func missingTypeIsNotText() async throws {
        let decoded = try await Self.decodedPage(Data("bytes".utf8), type: nil)
        #expect(throws: WebFetchFailure.notText(contentType: "application/octet-stream")) {
            try decoded.get()
        }
    }

    @Test("a JSON body decodes as text")
    func jsonDecodes() async throws {
        let json = #"{"name": "café"}"#
        let decoded = try await Self.decodedPage(Data(json.utf8), type: "application/json")
        #expect(try decoded.get() == json)
    }

    @Test("a charset=iso-8859-1 body decodes with that charset")
    func latin1Decodes() async throws {
        let latin1 = try #require("café".data(using: .isoLatin1))
        let decoded = try await Self.decodedPage(latin1, type: "text/plain; charset=iso-8859-1")
        #expect(try decoded.get() == "café")
    }

    @Test(
        "each text media type decodes as UTF-8 when it has no charset",
        arguments: [
            "text/plain", "TEXT/Plain", "text/html", "application/xml", "application/xhtml+xml",
            "application/ld+json", "application/rss+xml",
        ]
    )
    func textTypeDecodes(type: String) async throws {
        let text = "naïve"
        let decoded = try await Self.decodedPage(Data(text.utf8), type: type)
        #expect(try decoded.get() == text)
    }

    // MARK: - Failures

    @Test("a request that does not answer in time gives the timeout failure")
    func hangingRequestTimesOut() async throws {
        let (_, result) = try await Self.loadPage(.hang, timeout: Self.shortTimeout)
        #expect(throws: WebFetchFailure.timeout(url: Self.pageURL, limit: Self.shortTimeout)) {
            try result.get()
        }
    }

    @Test(
        "the timeout correction states the limit in seconds",
        arguments: [
            (defaultTimeout, "30 seconds"), (Duration.seconds(1), "1 second"),
            (halfSecond, "0.5 seconds"),
        ]
    )
    func timeoutMessageStatesSeconds(limit: Duration, words: String) {
        let failure = WebFetchFailure.timeout(url: "https://example.org/slow", limit: limit)
        #expect(failure.correctiveMessage == "The request timed out after \(words): https://example.org/slow")
    }

    @Test("a connection failure gives the network failure with the URL")
    func connectionFailureIsNetworkFailure() async throws {
        let (_, result) = try await Self.loadPage(.fail(.cannotConnectToHost))
        let failure = #expect(throws: WebFetchFailure.self) { try result.get() }
        #expect(failure?.correctiveMessage.hasPrefix("The request to \(Self.pageURL) failed: ") == true)
    }

    // MARK: - Request headers

    @Test("a request with no User-Agent sends the User-Agent of the policy")
    func policyUserAgentIsSent() async throws {
        let agent = "PolicyAgent/2.0"
        let (stub, result) = try await Self.loadPage(
            .respond(status: WebStub.okStatus, headers: [:], body: Data()),
            policy: WebFetchPolicy(userAgent: agent)
        )
        _ = try result.get()
        #expect(stub.requests.map { $0.headers[Self.userAgent] } == [agent])
    }

    @Test("a request with its own User-Agent keeps it")
    func ownUserAgentIsKept() async throws {
        let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        let stub = WebStub(routes: [
            Self.pageURL: .respond(status: WebStub.okStatus, headers: [:], body: Data()),
        ])
        var request = try WebStub.request(to: Self.pageURL)
        request.setValue(agent, forHTTPHeaderField: Self.userAgent)
        _ = try await stub.makeFetcher().load(request, timeout: WebStub.ampleTimeout).get()
        #expect(stub.requests.map { $0.headers[Self.userAgent] } == [agent])
    }

    @Test("the session sends no cookies, keeps no cookies, and has no URL cache")
    func sessionHasNoCookiesAndNoCache() {
        let callerConfiguration = WebStub(routes: [:]).sessionConfiguration
        let fetcher = WebFetcher(
            sessionConfiguration: callerConfiguration, policy: WebFetchPolicy(),
            addressGuard: WebAddressGuard(resolver: PublicHostResolver())
        )
        let configuration = fetcher.session.configuration
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(callerConfiguration.httpShouldSetCookies)
    }

    // MARK: - Guard

    @Test("a guarded request to a loopback address is refused and not sent")
    func guardedLoopbackIsRefused() async throws {
        let stub = WebStub(routes: [
            Self.searxngURL: .respond(status: WebStub.okStatus, headers: [:], body: Data()),
        ])
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.searxngURL), timeout: WebStub.ampleTimeout)
        let expected = WebGuardRefusal(reason: "the host 127.0.0.1 is on the blocklist")
        #expect(throws: WebFetchFailure.refused(expected)) { try result.get() }
        #expect(stub.requests.isEmpty)
    }

    @Test("with guarded: false, a request to http://127.0.0.1:8888/search is sent")
    func unguardedRequestIsSent() async throws {
        let body = Data(#"{"results": []}"#.utf8)
        let stub = WebStub(routes: [
            Self.searxngURL: .respond(status: WebStub.okStatus, headers: [:], body: body),
        ])
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.searxngURL), timeout: WebStub.ampleTimeout, guarded: false)
        #expect(try result.get().bytes == body)
        #expect(stub.requestedURLs == [Self.searxngURL])
    }
}
