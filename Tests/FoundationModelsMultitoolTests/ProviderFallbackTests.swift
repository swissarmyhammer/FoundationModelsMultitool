import Foundation
@testable import FoundationModelsMultitool
import Testing

/// Tests for `WebSearchChain`: each failure kind goes to the next provider and
/// adds one note, the first provider with hits wins, the all-fail correction,
/// the unsupported-field note, and the redaction of key values.
///
/// Each provider is a ``FakeSearchAdapter``, and a `WebStub` answers each
/// request, thus no test uses the network.
@Suite("ProviderFallback")
struct ProviderFallbackTests {
    /// The environment variable of the keyed provider in the tests.
    private static let keyVariable = "BRAVE_SEARCH_API_KEY"

    /// The key value of the keyed provider in the tests.
    private static let keyValue = "sk-test-fallback-key-0123"

    /// The status of a refused key.
    private static let unauthorizedStatus = 401

    /// The other status of a refused key.
    private static let forbiddenStatus = 403

    /// The status of a rate limit.
    private static let rateLimitStatus = 429

    /// The status of a server failure.
    private static let internalErrorStatus = 500

    /// The status of a server that is not available.
    private static let unavailableStatus = 503

    /// The time limit of a provider in the timeout test, in seconds.
    private static let shortTimeout: TimeInterval = 0.2

    /// The number of hits that a provider with hits gives.
    private static let hitCount = 3

    /// The URL of the endpoint of the fake provider `name`.
    ///
    /// The host is in lower case, because a session can make a host lower
    /// case, and the stub finds its row by the exact URL text.
    ///
    /// - Parameter name: The name of the provider.
    /// - Returns: The URL text.
    private static func endpoint(_ name: String) -> String {
        "https://\(name.lowercased()).example/search"
    }

    /// The URL of a URL text.
    ///
    /// - Parameter text: The absolute URL text.
    /// - Returns: The URL.
    /// - Throws: When `text` is not a URL.
    private static func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    /// A fake adapter whose endpoint is ``endpoint(_:)`` of its name.
    ///
    /// - Parameters:
    ///   - name: The name of the provider.
    ///   - supports: The query fields that the provider supports.
    /// - Returns: The adapter.
    private static func adapter(_ name: String, supports: Set<SearchFeature> = []) throws -> FakeSearchAdapter {
        try FakeSearchAdapter(name: name, endpoint: url(endpoint(name)), supports: supports)
    }

    /// The keyless first provider, `braveHTML`, with a fake adapter.
    ///
    /// - Returns: The provider and its adapter.
    private static func braveHTML() throws -> (WebSearchProvider, any SearchProviderAdapter) {
        try (.braveHTML, adapter("braveHTML"))
    }

    /// The keyless second provider, `duckDuckGoHTML`, with a fake adapter.
    ///
    /// - Parameter supports: The query fields that the provider supports.
    /// - Returns: The provider and its adapter.
    private static func duckDuckGoHTML(
        supports: Set<SearchFeature> = []
    ) throws -> (WebSearchProvider, any SearchProviderAdapter) {
        try (.duckDuckGoHTML, adapter("duckDuckGoHTML", supports: supports))
    }

    /// The keyed provider, `braveAPI`, whose key is in ``keyVariable``.
    ///
    /// - Returns: The provider and its adapter.
    private static func braveAPI() throws -> (WebSearchProvider, any SearchProviderAdapter) {
        try (.braveAPI(.environment(keyVariable)), adapter("braveAPI"))
    }

    /// A `200` reply whose body gives `count` hits in the line format of
    /// ``FakeSearchAdapter``.
    ///
    /// - Parameter count: The number of hits.
    /// - Returns: The reply.
    private static func hitsReply(count: Int = hitCount) -> WebStubReply {
        let lines = (1...count).map { "Result \($0)\thttps://result.example/\($0)" }
        return textReply(lines.joined(separator: "\n"))
    }

    /// The hits that ``hitsReply(count:)`` gives.
    ///
    /// - Parameter count: The number of hits.
    /// - Returns: The hits, with rank 1 first.
    private static func expectedHits(count: Int = hitCount) -> [WebHit] {
        (1...count).map { WebHit(rank: $0, title: "Result \($0)", url: "https://result.example/\($0)", snippet: "") }
    }

    /// A reply with `status` and `text` as the body.
    ///
    /// - Parameters:
    ///   - text: The body.
    ///   - status: The HTTP status.
    /// - Returns: The reply.
    private static func textReply(_ text: String, status: Int = WebStub.okStatus) -> WebStubReply {
        .respond(status: status, headers: ["Content-Type": "text/plain"], body: Data(text.utf8))
    }

    /// Makes a chain over `providers` that sends each request to `stub`.
    ///
    /// - Parameters:
    ///   - providers: The providers and their adapters, in order.
    ///   - stub: The stub that answers each request.
    ///   - environment: The environment dictionary of the call.
    ///   - policy: The fetch policy.
    /// - Returns: The chain.
    private static func chain(
        _ providers: [(WebSearchProvider, any SearchProviderAdapter)],
        stub: WebStub,
        environment: [String: String] = [:],
        policy: WebFetchPolicy = WebFetchPolicy()
    ) -> WebSearchChain {
        WebSearchChain(providers: providers, fetcher: stub.makeFetcher(policy: policy), environment: environment)
    }

    /// Runs a search whose first provider, `braveHTML`, gets `failing` and
    /// whose second provider, `duckDuckGoHTML`, gives hits.
    ///
    /// - Parameters:
    ///   - failing: The reply to the first provider.
    ///   - policy: The fetch policy.
    /// - Returns: The notes of the outcome.
    private static func notesAfterFirstProvider(
        gets failing: WebStubReply, policy: WebFetchPolicy = WebFetchPolicy()
    ) async throws -> [String] {
        let stub = WebStub(routes: [endpoint("braveHTML"): failing, endpoint("duckDuckGoHTML"): hitsReply()])
        let outcome = try await chain([braveHTML(), duckDuckGoHTML()], stub: stub, policy: policy)
            .search(SearchQuery(text: "swift"))
        let notes = try #require(outcome.hitNotes)
        #expect(outcome == .hits(provider: "duckDuckGoHTML", hits: expectedHits(), notes: notes))
        return notes
    }

    // MARK: - Each failure kind

    @Test("a key variable that is not set skips the provider with one note and sends no request")
    func missingKeySkips() async throws {
        let stub = WebStub(routes: [Self.endpoint("braveHTML"): Self.hitsReply()])
        let outcome = try await Self.chain([Self.braveAPI(), Self.braveHTML()], stub: stub)
            .search(SearchQuery(text: "swift"))
        #expect(
            outcome
                == .hits(
                    provider: "braveHTML", hits: Self.expectedHits(),
                    notes: ["braveAPI: skipped, BRAVE_SEARCH_API_KEY is not set."]))
        #expect(!stub.requestedURLs.contains(Self.endpoint("braveAPI")))
    }

    @Test("a refused key skips the provider with one note", arguments: [unauthorizedStatus, forbiddenStatus])
    func refusedKeySkips(status: Int) async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: Self.textReply("denied", status: status))
        #expect(notes == ["braveHTML: skipped, the API key was refused."])
    }

    @Test("a rate limit skips the provider with one note")
    func rateLimitSkips() async throws {
        let reply = Self.textReply("slow down", status: Self.rateLimitStatus)
        let notes = try await Self.notesAfterFirstProvider(gets: reply)
        #expect(notes == ["braveHTML: skipped, blocked (HTTP 429)."])
    }

    @Test("a server error skips the provider with one note", arguments: [internalErrorStatus, unavailableStatus])
    func serverErrorSkips(status: Int) async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: Self.textReply("broken", status: status))
        #expect(notes == ["braveHTML: skipped, server error (HTTP \(status))."])
    }

    @Test("a challenge page skips the provider with one note")
    func challengeSkips() async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: Self.textReply(FakeSearchAdapter.challengeMarker))
        #expect(notes == ["braveHTML: skipped, blocked by a challenge page."])
    }

    @Test("no results skips the provider with one note")
    func noResultsSkips() async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: Self.textReply(""))
        #expect(notes == ["braveHTML: skipped, no results."])
    }

    @Test("a response that the adapter cannot read skips the provider with one note")
    func parseFailureSkips() async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: Self.textReply("garbage"))
        #expect(notes == ["braveHTML: skipped, the response could not be read: bad line: garbage."])
    }

    @Test("a timeout skips the provider with one note")
    func timeoutSkips() async throws {
        let policy = WebFetchPolicy(searchTimeout: Self.shortTimeout)
        let notes = try await Self.notesAfterFirstProvider(gets: .hang, policy: policy)
        let endpoint = Self.endpoint("braveHTML")
        #expect(notes == ["braveHTML: skipped, the request timed out after 0.2 seconds: \(endpoint)."])
    }

    @Test("a network failure skips the provider with one note")
    func networkFailureSkips() async throws {
        let notes = try await Self.notesAfterFirstProvider(gets: .fail(.cannotConnectToHost))
        #expect(notes.count == 1)
        let lead = "braveHTML: skipped, the request to \(Self.endpoint("braveHTML")) failed: "
        #expect(notes.first?.hasPrefix(lead) == true)
    }

    @Test("a guard refusal skips the provider with one note and sends no request")
    func guardRefusalSkips() async throws {
        let loopback = try FakeSearchAdapter(name: "braveHTML", endpoint: Self.url("http://127.0.0.1/search"))
        let stub = WebStub(routes: [Self.endpoint("duckDuckGoHTML"): Self.hitsReply()])
        let outcome = try await Self.chain([(.braveHTML, loopback), Self.duckDuckGoHTML()], stub: stub)
            .search(SearchQuery(text: "swift"))
        #expect(
            outcome.hitNotes == [
                "braveHTML: skipped, the address is not allowed: the host 127.0.0.1 is on the blocklist."
            ])
        #expect(stub.requestedURLs == [Self.endpoint("duckDuckGoHTML")])
    }

    @Test("a request that the adapter cannot make skips the provider with one note")
    func requestFailureSkips() async throws {
        let broken = FakeSearchAdapter(name: "braveHTML", endpoint: nil)
        let stub = WebStub(routes: [Self.endpoint("duckDuckGoHTML"): Self.hitsReply()])
        let outcome = try await Self.chain([(.braveHTML, broken), Self.duckDuckGoHTML()], stub: stub)
            .search(SearchQuery(text: "swift"))
        #expect(
            outcome.hitNotes == [
                "braveHTML: skipped, the request could not be made: the fake adapter has no endpoint."
            ])
    }

    // MARK: - The winner

    @Test("the first provider that gives hits wins, and later providers get no request")
    func firstProviderWithHitsWins() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveHTML"): Self.hitsReply(),
            Self.endpoint("duckDuckGoHTML"): Self.hitsReply()
        ])
        let outcome = try await Self.chain([Self.braveHTML(), Self.duckDuckGoHTML()], stub: stub)
            .search(SearchQuery(text: "swift"))
        #expect(outcome == .hits(provider: "braveHTML", hits: Self.expectedHits(), notes: []))
        #expect(stub.requestedURLs == [Self.endpoint("braveHTML")])
    }

    @Test("the adapter gets the key value that the environment holds at the time of the call")
    func adapterGetsKeyFromEnvironment() async throws {
        let stub = WebStub(routes: [Self.endpoint("braveAPI"): Self.hitsReply()])
        let outcome = try await Self.chain(
            [Self.braveAPI()], stub: stub, environment: [Self.keyVariable: Self.keyValue]
        ).search(SearchQuery(text: "swift"))
        #expect(outcome == .hits(provider: "braveAPI", hits: Self.expectedHits(), notes: []))
        #expect(stub.requests.first?.headers[FakeSearchAdapter.keyHeader] == Self.keyValue)
    }

    @Test("an adapter of host configuration sends its request with no guard check")
    func hostConfigurationIsUnguarded() async throws {
        let local = "http://127.0.0.1/search"
        let searxng = try FakeSearchAdapter(name: "searxng", endpoint: Self.url(local), isHostConfiguration: true)
        let stub = WebStub(routes: [local: Self.hitsReply()])
        let base = try Self.url("http://127.0.0.1/")
        let outcome = await Self.chain([(.searxng(base), searxng)], stub: stub).search(SearchQuery(text: "swift"))
        #expect(outcome == .hits(provider: "searxng", hits: Self.expectedHits(), notes: []))
    }

    // MARK: - All fail

    @Test("when all providers fail, the correction names each provider and its failure in order")
    func allFailGivesOneCorrection() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveHTML"): Self.textReply("slow down", status: Self.rateLimitStatus),
            Self.endpoint("duckDuckGoHTML"): Self.textReply("")
        ])
        let outcome = try await Self.chain([Self.braveHTML(), Self.duckDuckGoHTML()], stub: stub)
            .search(SearchQuery(text: "swift"))
        #expect(
            outcome
                == .correction(
                    "No search provider gave results. braveHTML: blocked (HTTP 429). duckDuckGoHTML: no results."))
    }

    // MARK: - Unsupported fields

    @Test("each query field that the winner does not support adds one note")
    func unsupportedFieldAddsNote() async throws {
        let stub = WebStub(routes: [Self.endpoint("duckDuckGoHTML"): Self.hitsReply()])
        let query = SearchQuery(text: "swift", count: Self.hitCount, freshness: .week, site: "swift.org")
        let outcome = try await Self.chain([Self.duckDuckGoHTML(supports: [.site, .count])], stub: stub).search(query)
        #expect(
            outcome
                == .hits(
                    provider: "duckDuckGoHTML", hits: Self.expectedHits(),
                    notes: ["freshness is not supported by duckDuckGoHTML and was ignored."]))
    }

    @Test("a query field that the caller did not set adds no note")
    func unsetFieldAddsNoNote() async throws {
        let stub = WebStub(routes: [Self.endpoint("duckDuckGoHTML"): Self.hitsReply()])
        let outcome = try await Self.chain([Self.duckDuckGoHTML()], stub: stub).search(SearchQuery(text: "swift"))
        #expect(outcome == .hits(provider: "duckDuckGoHTML", hits: Self.expectedHits(), notes: []))
    }

    // MARK: - Redaction

    @Test("a provider error that echoes the key shows <redacted> in the note")
    func noteRedactsKey() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveAPI"): Self.textReply("key \(Self.keyValue) is bad"),
            Self.endpoint("braveHTML"): Self.hitsReply()
        ])
        let outcome = try await Self.chain(
            [Self.braveAPI(), Self.braveHTML()], stub: stub, environment: [Self.keyVariable: Self.keyValue]
        ).search(SearchQuery(text: "swift"))
        #expect(
            outcome
                == .hits(
                    provider: "braveHTML", hits: Self.expectedHits(),
                    notes: ["braveAPI: skipped, the response could not be read: bad line: key <redacted> is bad."]))
    }

    @Test("when all providers fail and one error echoes the key, the correction shows <redacted>")
    func correctionRedactsKey() async throws {
        let stub = WebStub(routes: [
            Self.endpoint("braveAPI"): Self.textReply("key \(Self.keyValue) is bad"),
            Self.endpoint("braveHTML"): Self.textReply("")
        ])
        let outcome = try await Self.chain(
            [Self.braveAPI(), Self.braveHTML()], stub: stub, environment: [Self.keyVariable: Self.keyValue]
        ).search(SearchQuery(text: "swift"))
        let correction = try #require(outcome.correctionText)
        #expect(!correction.contains(Self.keyValue))
        #expect(
            correction
                == "No search provider gave results. braveAPI: the response could not be read: "
                + "bad line: key <redacted> is bad. braveHTML: no results.")
    }
}
