import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for the redirect check of `WebFetcher`: the guard checks each
/// redirect hop, and the fetcher stops after `maxRedirects` hops.
///
/// A `WebStub` answers each request, thus no test uses the network.
@Suite("WebRedirectGuard")
struct WebRedirectGuardTests {
    /// The URL of the first request of a redirect test.
    private static let startURL = "https://start.example/"

    /// The URL of the SearXNG instance that a host runs on its own computer.
    private static let searxngURL = "http://127.0.0.1:8888/search"

    /// The URL of the cloud metadata service.
    private static let metadataURL = "http://169.254.169.254/"

    /// The URL of the loopback address.
    private static let loopbackURL = "http://127.0.0.1/"

    /// The body of the page at the end of a redirect chain.
    private static let finalBody = Data("the end of the chain".utf8)

    /// The URL of hop `index` of a redirect chain. Hop 0 is the first request.
    private static func hopURL(_ index: Int) -> String {
        "https://hops.example/\(index)"
    }

    /// Makes a stub whose chain has `hops` redirects before a `200` page.
    ///
    /// - Parameter hops: The number of redirects.
    /// - Returns: The stub. The first request goes to `hopURL(0)`, and the
    ///   page is at `hopURL(hops)`.
    private static func chainStub(hops: Int) throws -> WebStub {
        var routes: [String: WebStubReply] = [:]
        for index in 0 ..< hops {
            routes[hopURL(index)] = try .redirect(location: #require(URL(string: hopURL(index + 1))))
        }
        routes[hopURL(hops)] = .respond(status: WebStub.okStatus, headers: [:], body: finalBody)
        return WebStub(routes: routes)
    }

    @Test("a redirect to http://127.0.0.1/ is refused before a request goes to that address")
    func redirectToLoopbackIsRefused() async throws {
        let stub = try WebStub(routes: [
            Self.startURL: .redirect(location: #require(URL(string: Self.loopbackURL))),
        ])
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.startURL), timeout: WebStub.ampleTimeout)
        let expected = WebGuardRefusal(reason: "the host 127.0.0.1 is on the blocklist")
        #expect(throws: WebFetchFailure.refused(expected)) { try result.get() }
        #expect(stub.requestedURLs == [Self.startURL])
    }

    @Test("a chain of exactly maxRedirects hops is followed to its page")
    func tenHopsAreFollowed() async throws {
        let hops = WebFetchPolicy().maxRedirects
        let stub = try Self.chainStub(hops: hops)
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.hopURL(0)), timeout: WebStub.ampleTimeout)
        let body = try result.get()
        #expect(body.url.absoluteString == Self.hopURL(hops))
        #expect(body.bytes == Self.finalBody)
    }

    @Test("the eleventh redirect hop is refused")
    func eleventhHopIsRefused() async throws {
        let limit = WebFetchPolicy().maxRedirects
        let stub = try Self.chainStub(hops: limit + 1)
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.hopURL(0)), timeout: WebStub.ampleTimeout)
        #expect(throws: WebFetchFailure.tooManyRedirects(url: Self.hopURL(0), limit: limit)) {
            try result.get()
        }
        #expect(stub.requestedURLs == (0 ... limit).map(Self.hopURL))
    }

    @Test("a smaller maxRedirects stops the chain sooner")
    func policyLimitIsUsed() async throws {
        let limit = 2
        let stub = try Self.chainStub(hops: limit + 1)
        let result = try await stub.makeFetcher(policy: WebFetchPolicy(maxRedirects: limit))
            .load(WebStub.request(to: Self.hopURL(0)), timeout: WebStub.ampleTimeout)
        #expect(throws: WebFetchFailure.tooManyRedirects(url: Self.hopURL(0), limit: limit)) {
            try result.get()
        }
    }

    @Test("an unguarded request is sent, and its redirect to the metadata service is refused")
    func redirectOfUnguardedRequestIsRefused() async throws {
        let stub = try WebStub(routes: [
            Self.searxngURL: .redirect(location: #require(URL(string: Self.metadataURL))),
        ])
        let result = try await stub.makeFetcher()
            .load(WebStub.request(to: Self.searxngURL), timeout: WebStub.ampleTimeout, guarded: false)
        let expected = WebGuardRefusal(reason: "the host 169.254.169.254 is on the blocklist")
        #expect(throws: WebFetchFailure.refused(expected)) { try result.get() }
        #expect(stub.requestedURLs == [Self.searxngURL])
    }
}
